import Foundation
import CoreMotion
import Network
import Combine

/// Streams CMHeadphoneMotionManager attitude as OpenTrack UDP packets:
/// 48 bytes = 6 little-endian Doubles: X, Y, Z, yaw, pitch, roll
/// (position unused → 0; rotation in degrees). Default port 4242.
final class MotionStreamer: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published var statusText: String = "未开始"
    @Published var headphoneStatus: String = "等待耳机"
    @Published var recenterText: String = ""
    @Published var yawDeg: Double = 0
    @Published var pitchDeg: Double = 0
    @Published var rollDeg: Double = 0
    @Published var isStreaming: Bool = false
    @Published var packetCount: UInt64 = 0
    @Published var lastError: String = ""

    private let motionManager = CMHeadphoneMotionManager()
    private var connection: NWConnection?
    private let networkQueue = DispatchQueue(label: "com.airpodsmouse.udp", qos: .userInteractive)
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.airpodsmouse.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()

    private let lock = NSLock()
    private var sessionID = UUID()
    private var referenceAttitude: CMAttitude?
    private var latestAttitude: CMAttitude?

    override init() {
        super.init()
        motionManager.delegate = self
    }

    func start(host: String, portText: String) {
        invalidateSession()
        tearDown()
        isStreaming = false
        lastError = ""
        recenterText = ""
        packetCount = 0

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            fail("请填写电脑的局域网 IP")
            return
        }

        let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(trimmedPort), port > 0 else {
            fail("端口无效，请填写 1–65535（默认 4242）")
            return
        }

        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            fail("运动与健身权限已关闭。请打开「设置 → 隐私与安全性 → 运动与健身」，允许本 App。")
            return
        case .notDetermined, .authorized:
            break
        @unknown default:
            break
        }

        guard motionManager.isDeviceMotionAvailable else {
            headphoneStatus = "未连接"
            fail("没有检测到支持头部追踪的耳机。请连接并戴上 AirPods Pro、AirPods Max 或 AirPods（第 3 代）。若弹出权限请求，点允许后再试一次。")
            return
        }
        headphoneStatus = "耳机已连接"

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            fail("端口无效，请填写 1–65535（默认 4242）")
            return
        }

        let session = beginSession()
        let conn = NWConnection(host: NWEndpoint.Host(trimmedHost), port: nwPort, using: .udp)
        lock.lock()
        connection = conn
        referenceAttitude = nil
        latestAttitude = nil
        lock.unlock()

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self, self.isCurrent(session) else { return }
                switch state {
                case .ready:
                    self.statusText = "UDP 就绪 → \(trimmedHost):\(port)"
                    self.lastError = ""
                case .failed(let err):
                    self.statusText = "UDP 失败: \(err.localizedDescription)"
                    self.lastError = err.localizedDescription
                case .waiting(let err):
                    self.statusText = "UDP 等待: \(err.localizedDescription)"
                    self.lastError = err.localizedDescription
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        conn.start(queue: networkQueue)

        // CMHeadphoneMotionManager delivers updates on an OperationQueue, not a DispatchQueue.
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self = self, self.isCurrent(session) else { return }
            if let error = error {
                DispatchQueue.main.async {
                    guard self.isCurrent(session) else { return }
                    self.lastError = error.localizedDescription
                    self.statusText = "运动错误: \(error.localizedDescription)"
                }
                return
            }
            guard let motion = motion else { return }
            self.handle(motion, session: session)
        }

        isStreaming = true
        statusText = "正在推流 → \(trimmedHost):\(port)"
    }

    func stop() {
        invalidateSession()
        tearDown()
        isStreaming = false
        statusText = "已停止"
    }

    /// Current head pose becomes yaw/pitch/roll = 0 in the packets sent to the PC.
    func recenter() {
        lock.lock()
        let captured = latestAttitude?.copy() as? CMAttitude
        if captured != nil {
            referenceAttitude = captured
        }
        lock.unlock()

        if captured == nil {
            lastError = "还没有姿态数据。请先开始推流，并确认耳机已戴好。"
            return
        }
        yawDeg = 0
        pitchDeg = 0
        rollDeg = 0
        lastError = ""
        recenterText = "已回中：当前朝向当作正面"
    }

    private func fail(_ message: String) {
        invalidateSession()
        statusText = message
        lastError = message
        isStreaming = false
    }

    private func beginSession() -> UUID {
        let session = UUID()
        lock.lock()
        sessionID = session
        lock.unlock()
        return session
    }

    private func invalidateSession() {
        lock.lock()
        sessionID = UUID()
        lock.unlock()
    }

    private func isCurrent(_ session: UUID) -> Bool {
        lock.lock()
        let current = sessionID
        lock.unlock()
        return current == session
    }

    private func tearDown() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        lock.lock()
        let conn = connection
        connection = nil
        referenceAttitude = nil
        latestAttitude = nil
        lock.unlock()
        conn?.cancel()
    }

    private func handle(_ motion: CMDeviceMotion, session: UUID) {
        guard isCurrent(session) else { return }
        guard let attitude = motion.attitude.copy() as? CMAttitude else { return }

        lock.lock()
        if referenceAttitude == nil {
            referenceAttitude = attitude.copy() as? CMAttitude
        }
        latestAttitude = attitude.copy() as? CMAttitude
        if let reference = referenceAttitude {
            attitude.multiply(byInverseOf: reference)
        }
        let conn = connection
        lock.unlock()

        let yaw = attitude.yaw * 180.0 / .pi
        let pitch = attitude.pitch * 180.0 / .pi
        let roll = attitude.roll * 180.0 / .pi
        let data = Self.openTrackPacket(yaw: yaw, pitch: pitch, roll: roll)

        conn?.send(content: data, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self, self.isCurrent(session) else { return }
                if let error = error {
                    self.lastError = error.localizedDescription
                    return
                }
                self.packetCount += 1
                self.lastError = ""
            }
        })

        DispatchQueue.main.async {
            guard self.isCurrent(session) else { return }
            self.yawDeg = yaw
            self.pitchDeg = pitch
            self.rollDeg = roll
        }
    }

    /// OpenTrack UDP payload: 6 little-endian doubles (48 bytes). Apple platforms are little-endian.
    private static func openTrackPacket(yaw: Double, pitch: Double, roll: Double) -> Data {
        var values: [Double] = [0, 0, 0, yaw, pitch, roll]
        return values.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return Data() }
            return Data(bytes: base, count: buffer.count * MemoryLayout<Double>.stride)
        }
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            self.headphoneStatus = "耳机已连接"
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            self.headphoneStatus = "耳机已断开"
            if self.isStreaming {
                self.lastError = "耳机已断开，头部数据会暂停。重新戴上后会继续发送。"
            }
        }
    }
}
