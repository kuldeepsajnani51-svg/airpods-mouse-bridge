import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var streamer = MotionStreamer()
    @AppStorage("pcHost") private var host: String = "192.168.1.100"
    @AppStorage("pcPort") private var portText: String = "4242"
    @State private var keepAwake = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("电脑目标（OpenTrack UDP）"), footer: Text("填写 Windows 的局域网 IPv4（在电脑命令行输入 ipconfig 查看）。修改 IP 或端口后，需要先停止再点开始。")) {
                    TextField("PC 局域网 IP", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    TextField("端口（默认 4242）", text: $portText)
                        .keyboardType(.numberPad)
                }

                Section(header: Text("状态")) {
                    labeled("耳机", streamer.headphoneStatus)
                    labeled("连接", streamer.statusText)
                    labeled("Yaw", String(format: "%.1f°", streamer.yawDeg))
                    labeled("Pitch", String(format: "%.1f°", streamer.pitchDeg))
                    labeled("Roll", String(format: "%.1f°", streamer.rollDeg))
                    labeled("已发送包", "\(streamer.packetCount)")
                    if !streamer.recenterText.isEmpty {
                        Text(streamer.recenterText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    if !streamer.lastError.isEmpty && streamer.lastError != streamer.statusText {
                        Text(streamer.lastError)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section(footer: Text("开始时会把当时的朝向当作正面。脸正对屏幕后点「回中」，Yaw / Pitch / Roll 会接近 0，并发给电脑。协议：每个 UDP 包 48 字节，6 个小端 double（X Y Z Yaw Pitch Roll），位置为 0，角度为度。")) {
                    Button(streamer.isStreaming ? "停止" : "开始推流") {
                        if streamer.isStreaming {
                            streamer.stop()
                            UIApplication.shared.isIdleTimerDisabled = false
                        } else {
                            streamer.start(host: host, portText: portText)
                            if streamer.isStreaming && keepAwake {
                                UIApplication.shared.isIdleTimerDisabled = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(streamer.isStreaming ? .red : .blue)

                    Button("回中（当前朝向当作正面）") {
                        streamer.recenter()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!streamer.isStreaming)

                    Toggle("推流时保持屏幕常亮", isOn: $keepAwake)
                }
            }
            .navigationTitle("AirPods → 鼠标")
        }
        .navigationViewStyle(.stack)
        .onChange(of: keepAwake) { enabled in
            if streamer.isStreaming {
                UIApplication.shared.isIdleTimerDisabled = enabled
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && streamer.isStreaming && keepAwake {
                UIApplication.shared.isIdleTimerDisabled = true
            } else if phase != .active {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
