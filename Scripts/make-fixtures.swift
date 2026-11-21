import AppKit

@main struct MakeFixtures {
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var file = try SampleImage.file()
        try file.source.write(to:output.appendingPathComponent("Sample.png"))
        var marker = Annotation(tool:.marker); marker.color = InkColor(1,0.85,0.25); marker.brushSize = 0.35; marker.lineWidth = TelegramBrushMetrics.width(.marker,size:file.size,value:0.35)
        marker.points = stride(from:130,through:610,by:12).map { CGPoint(x:$0,y:238) }; file.annotations.append(marker)
        var rect = Annotation(tool:.rectangle); rect.rect = CGRect(x:438,y:295,width:302,height:260); rect.color = .coral; rect.shapeWidth = 0.15; rect.lineWidth = 19.2; file.annotations.append(rect)
        var arrow = Annotation(tool:.line); arrow.points = [CGPoint(x:1000,y:230),CGPoint(x:900,y:250),CGPoint(x:770,y:340)]; arrow.vectorWidth = 0.15; arrow.lineWidth = 19.2; file.annotations.append(arrow)
        var text = Annotation(tool:.text); text.rect = CGRect(x:800,y:150,width:260,height:60); text.text = "Start here"; text.fontSize = 36; text.color = .coral; text.rotation = -0.07; file.annotations.append(text)
        var check = Annotation(tool:.pen); check.color = InkColor(0.1,0.65,0.43); check.lineWidth = 8
        check.points = [CGPoint(x:315,y:560),CGPoint(x:338,y:580),CGPoint(x:375,y:530)]; file.annotations.append(check)
        var star = Annotation(tool:.star); star.rect = CGRect(x:970,y:530,width:200,height:200); star.color = InkColor(1,0.76,0.15); star.filled = true; star.rotation = 0.15; file.annotations.append(star)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(file).write(to:output.appendingPathComponent("Example.markup"))
        try ImageCodec.encode(MarkupRenderer().render(file),type:.png).write(to:output.appendingPathComponent("Example.png"))
    }
}
