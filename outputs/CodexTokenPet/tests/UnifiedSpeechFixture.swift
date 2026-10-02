import Foundation
@main struct Check {
 static func main() throws {
  let data = try Data(contentsOf: UnifiedSpeech.directory.appendingPathComponent("manifest.json"))
  let json = try JSONSerialization.jsonObject(with: data) as! [String:Any]
  let clips = json["clips"] as! [[String:Any]]
  let sources = Set(clips.map { $0["source"] as! String })
  for source in sources {
   let url = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(source)
   precondition(UnifiedSpeech.resolve(url,volume:0) == nil)
   for (volume,percent,player) in [(Float(0.5),100,Float(0.5)),(1,100,1),(1.591,160,1),(2,200,1)] {
    let result = UnifiedSpeech.resolve(url, volume:volume)!
    precondition(result.percent == percent && result.playerVolume == player)
    precondition(result.url.path.contains("/normalized/"))
   }
  }
  let fallback = URL(fileURLWithPath: CommandLine.arguments[0])
  precondition(UnifiedSpeech.resolve(fallback,volume:1.6)?.url == fallback)
  print("PASS: \(sources.count) real source paths, mute/50/100/160/200% routing and audible missing-bank fallback")
 }
}
