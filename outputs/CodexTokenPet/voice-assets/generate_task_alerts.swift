import Foundation

// Build-time only. Playback reads the resulting WAV files and never calls TTS.
let endpoint = URL(string: "http://127.0.0.1:42003")!
let voiceName = "爱弥斯_桌宠克隆音色_v1"
let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("task-alerts/raw", isDirectory: true)
let clips = [("complete.wav", "你的任务完成啦"), ("problem.wav", "你的任务遇到问题啦")]

func request(_ value: URLRequest) throws -> Data {
    let gate = DispatchSemaphore(value: 0)
    var result: Result<Data, Error>!
    URLSession.shared.dataTask(with: value) { data, response, error in
        defer { gate.signal() }
        if let error { result = .failure(error); return }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let data else {
            result = .failure(NSError(domain: "TaskAlerts", code: status))
            return
        }
        result = .success(data)
    }.resume()
    gate.wait()
    return try result.get()
}

var prompts = URLRequest(url: endpoint.appendingPathComponent("api/v1/base/prompts"))
prompts.timeoutInterval = 8
let root = try JSONSerialization.jsonObject(with: request(prompts)) as! [String: Any]
let available = root["prompts"] as! [[String: Any]]
guard let promptID = available.first(where: { $0["name"] as? String == voiceName })?["prompt_id"] as? String else {
    throw NSError(domain: "TaskAlerts", code: 1, userInfo: [NSLocalizedDescriptionKey: "克隆音色不存在：\(voiceName)"])
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (file, text) in clips {
    var generation = URLRequest(url: endpoint.appendingPathComponent("api/v1/base/generate-with-prompt"))
    generation.httpMethod = "POST"
    generation.timeoutInterval = 180
    generation.setValue("application/json", forHTTPHeaderField: "Content-Type")
    generation.setValue("your-api-key-1", forHTTPHeaderField: "X-API-Key")
    generation.httpBody = try JSONSerialization.data(withJSONObject: ["prompt_id": promptID, "text": text, "language": "Chinese", "speed": 1.0, "response_format": "base64"])
    let result = try JSONSerialization.jsonObject(with: request(generation)) as! [String: Any]
    guard let encoded = result["audio"] as? String, let audio = Data(base64Encoded: encoded), !audio.isEmpty else {
        throw NSError(domain: "TaskAlerts", code: 2, userInfo: [NSLocalizedDescriptionKey: "没有生成 \(file)"])
    }
    try audio.write(to: output.appendingPathComponent(file), options: .atomic)
    print("\(file): \(text), \(audio.count) bytes")
}
