import Foundation

let baseURL = URL(string: "http://127.0.0.1:42003")!
let voiceName = "爱弥斯_桌宠克隆音色_v1"
let apiKey = "your-api-key-1"
let lines = [
    "嘿，我在这里呢。",
    "今天也一起加油吧。",
    "别着急，慢慢来就好。",
    "有我陪着你呢。",
    "要记得休息一下哦。"
]
let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("click-clone", isDirectory: true)

func request(_ request: URLRequest) throws -> Data {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Data, Error>!
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error { result = .failure(error); return }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let data else {
            result = .failure(NSError(domain: "ClickVoiceGenerator", code: status))
            return
        }
        result = .success(data)
    }.resume()
    semaphore.wait()
    return try result.get()
}

var promptsRequest = URLRequest(url: baseURL.appendingPathComponent("api/v1/base/prompts"))
promptsRequest.timeoutInterval = 8
let promptsData = try request(promptsRequest)
let promptsRoot = try JSONSerialization.jsonObject(with: promptsData) as! [String: Any]
let prompts = promptsRoot["prompts"] as! [[String: Any]]
guard let promptID = prompts.first(where: { $0["name"] as? String == voiceName })?["prompt_id"] as? String else {
    throw NSError(domain: "ClickVoiceGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到克隆音色：\(voiceName)"])
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var clips: [[String: Any]] = []
for (index, text) in lines.enumerated() {
    var generation = URLRequest(url: baseURL.appendingPathComponent("api/v1/base/generate-with-prompt"))
    generation.httpMethod = "POST"
    generation.timeoutInterval = 180
    generation.setValue("application/json", forHTTPHeaderField: "Content-Type")
    generation.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    generation.httpBody = try JSONSerialization.data(withJSONObject: [
        "prompt_id": promptID,
        "text": text,
        "language": "Chinese",
        "speed": 1.0,
        "response_format": "base64"
    ])
    let responseData = try request(generation)
    let response = try JSONSerialization.jsonObject(with: responseData) as! [String: Any]
    guard let encoded = response["audio"] as? String, let audio = Data(base64Encoded: encoded), !audio.isEmpty else {
        throw NSError(domain: "ClickVoiceGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "第 \(index + 1) 句没有返回音频"])
    }
    let file = String(format: "%02d.wav", index + 1)
    try audio.write(to: output.appendingPathComponent(file), options: .atomic)
    clips.append(["file": file, "text": text])
    print("saved \(file): \(text)")
}

let manifest: [String: Any] = [
    "version": 1,
    "voice": voiceName,
    "provider": "Pinokio Qwen3-TTS MLX HTTP API",
    "playback": "Bundled WAV; no TTS request during clicks",
    "clips": clips
]
let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try manifestData.write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
