// AppKit adaptation of Telegram ColorPickerScreen.swift. GPL-2.0-or-later.
// The 12 × 10 palette, spectrum artwork/compositing, selection geometry and modes are retained.
import AppKit

let telegramPaletteColors: [UInt32] = [
    0xffffff, 0xebebeb, 0xd6d6d6, 0xc2c2c2, 0xadadad, 0x999999, 0x858585, 0x707070, 0x5c5c5c, 0x474747, 0x333333, 0x000000,
    0x00374a, 0x011d57, 0x11053b, 0x2e063d, 0x3c071b, 0x5c0701, 0x5a1c00, 0x583300, 0x563d00, 0x666100, 0x4f5504, 0x263e0f,
    0x004d65, 0x012f7b, 0x1a0a52, 0x450d59, 0x551029, 0x831100, 0x7b2900, 0x7a4a00, 0x785800, 0x8d8602, 0x6f760a, 0x38571a,
    0x016e8f, 0x0042a9, 0x2c0977, 0x61187c, 0x791a3d, 0xb51a00, 0xad3e00, 0xa96800, 0xa67b01, 0xc4bc00, 0x9ba50e, 0x4e7a27,
    0x008cb4, 0x0056d6, 0x371a94, 0x7a219e, 0x99244f, 0xe22400, 0xda5100, 0xd38301, 0xd19d01, 0xf5ec00, 0xc3d117, 0x669d34,
    0x00a1d8, 0x0061fe, 0x4d22b2, 0x982abc, 0xb92d5d, 0xff4015, 0xff6a00, 0xffab01, 0xfdc700, 0xfefb41, 0xd9ec37, 0x76bb40,
    0x01c7fc, 0x3a87fe, 0x5e30eb, 0xbe38f3, 0xe63b7a, 0xff6250, 0xff8648, 0xfeb43f, 0xfecb3e, 0xfff76b, 0xe4ef65, 0x96d35f,
    0x52d6fc, 0x74a7ff, 0x864ffe, 0xd357fe, 0xee719e, 0xff8c82, 0xffa57d, 0xffc777, 0xffd977, 0xfff994, 0xeaf28f, 0xb1dd8b,
    0x93e3fd, 0xa7c6ff, 0xb18cfe, 0xe292fe, 0xf4a4c0, 0xffb5af, 0xffc5ab, 0xffd9a8, 0xfee4a8, 0xfffbb9, 0xf2f7b7, 0xcde8b5,
    0xcbf0ff, 0xd3e2ff, 0xd9c9fe, 0xefcaff, 0xf9d3e0, 0xffdbd8, 0xffe2d6, 0xffecd4, 0xfff2d5, 0xfefcdd, 0xf7fadb, 0xdfeed4
]


final class TelegramColorField:NSView {
    var mode=0 { didSet { needsDisplay=true } }
    var color=InkColor(rgb:0xff453a) { didSet { needsDisplay=true } }
    var selected:((InkColor)->Void)?
    private var spectrum:CGImage?
    private var spectrumBytes:[UInt8]=[]
    private var spectrumStride=360*4
    private var point:CGPoint?
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        setAccessibilityElement(true);setAccessibilityRole(.image);setAccessibilityLabel("Color grid or spectrum")
    }
    required init?(coder:NSCoder) { fatalError() }
    static func gridColor(at point:CGPoint,size:CGSize) -> InkColor? {
        guard point.x>=0,point.y>=0,point.x<=size.width,point.y<=size.height,size.width>0,size.height>0 else { return nil }
        let row=max(0,min(9,Int(point.y/size.height*10)))
        let col=max(0,min(11,Int(point.x/size.width*12)))
        return InkColor(rgb:telegramPaletteColors[row*12+col])
    }
    private func loadSpectrum() {
        guard spectrum == nil,let c=try? ImageCodec.context(width:360,height:300) else { return }
        for name in ["spectrum","grayscale"] {
            if let url=Bundle.main.url(forResource:name,withExtension:"png"),let image=NSImage(contentsOf:url)?.cgImage {
                ImageCodec.draw(image,in:CGRect(x:0,y:0,width:360,height:300),context:c)
            }
        }
        spectrum=c.makeImage();spectrumStride=c.bytesPerRow
        if let data=c.data { spectrumBytes=Array(UnsafeBufferPointer(start:data.assumingMemoryBound(to:UInt8.self),count:c.bytesPerRow*c.height)) }
    }
    override func draw(_ dirtyRect:NSRect) {
        guard let c=UIGraphicsGetCurrentContext() else { return }
        c.saveGState();c.addPath(CGPath(roundedRect:bounds,cornerWidth:10,cornerHeight:10,transform:nil));c.clip()
        if mode == 0 {
            let side=bounds.width/12
            for i in telegramPaletteColors.indices { c.setFillColor(NSColor(rgb:telegramPaletteColors[i]).cgColor);c.fill(CGRect(x:CGFloat(i%12)*side,y:CGFloat(i/12)*side,width:side,height:side)) }
        } else { loadSpectrum();if let spectrum { ImageCodec.draw(spectrum,in:bounds,context:c) } }
        c.restoreGState()
        if mode == 0,let index=telegramPaletteColors.firstIndex(where:{ InkColor(rgb:$0).withUpdatedAlpha(CGFloat(color.alpha)) == color }) {
            let side=bounds.width/12
            let r=CGRect(x:CGFloat(index%12)*side,y:CGFloat(index/12)*side,width:side,height:side).insetBy(dx:1.25,dy:1.25)
            c.setStrokeColor((color.ns.lightness<0.5 ? NSColor.white : NSColor(rgb:0x1a1a1c)).cgColor);c.setLineWidth(2.5)
            c.addPath(CGPath(roundedRect:r,cornerWidth:2,cornerHeight:2,transform:nil));c.strokePath()
        } else if mode == 1,let point {
            let r=CGRect(x:point.x-12,y:point.y-12,width:24,height:24)
            c.setShadow(offset:.zero,blur:9,color:NSColor.black.withAlphaComponent(0.3).cgColor)
            c.setFillColor(color.ns.cgColor);c.fillEllipse(in:r);c.setStrokeColor(NSColor.white.cgColor);c.setLineWidth(3);c.strokeEllipse(in:r)
        }
    }
    private func choose(_ event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        let clamped=CGPoint(x:max(0,min(bounds.width,p.x)),y:max(0,min(bounds.height,p.y)))
        if mode == 0 { if let ink=Self.gridColor(at:clamped,size:bounds.size) { selected?(ink.withUpdatedAlpha(CGFloat(color.alpha))) } }
        else {
            loadSpectrum();guard !spectrumBytes.isEmpty else { return }
            let x=min(359,Int(clamped.x/bounds.width*360)),y=min(299,Int(clamped.y/bounds.height*300)),offset=y*spectrumStride+x*4
            point=clamped
            selected?(InkColor(Double(spectrumBytes[offset])/255,Double(spectrumBytes[offset+1])/255,Double(spectrumBytes[offset+2])/255,color.alpha))
        }
    }
    override func mouseDown(with event:NSEvent) { choose(event) }
    override func mouseDragged(with event:NSEvent) { choose(event) }
}

final class TelegramColorPicker:NSViewController {
    var color:InkColor { didSet { if isViewLoaded { refresh() } } }
    var updated:((InkColor)->Void)?
    var sampleImage: (() -> Void)?
    private let field=TelegramColorField(frame:.zero)
    private var sliders:[NSSlider]=[]
    private var fields:[NSTextField]=[]
    private var slidersView:NSStackView!
    private var alpha:NSSlider!
    private var hex:NSTextField!
    private let opacityValue = NSTextField(string: "")
    private let preview = NSColorWell()
    private let presets: [UInt32] = [0x000000, 0x0161fd, 0x32c759, 0xffcc02, 0xff3a30]

    init(color:InkColor) { self.color=color;super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError() }
    override func loadView() {
        view=NSView(frame:CGRect(x:0,y:0,width:400,height:550))
        let root=NSStackView();root.orientation = .vertical;root.spacing=16;root.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),root.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),root.topAnchor.constraint(equalTo:view.topAnchor,constant:20),root.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-20)])
        let title=NSTextField(labelWithString:"Colors");title.font = .systemFont(ofSize:18,weight:.semibold);root.addArrangedSubview(title)
        let mode=NSSegmentedControl(labels:["Grid","Spectrum","Sliders"],trackingMode:.selectOne,target:self,action:#selector(selectMode(_:)));mode.selectedSegment=0;root.addArrangedSubview(mode)
        field.widthAnchor.constraint(equalToConstant:360).isActive=true;field.heightAnchor.constraint(equalToConstant:300).isActive=true;root.addArrangedSubview(field)
        field.selected={ [weak self] in self?.commit($0) }
        slidersView=NSStackView();slidersView.orientation = .vertical;slidersView.spacing=24
        slidersView.widthAnchor.constraint(equalToConstant:360).isActive=true;slidersView.heightAnchor.constraint(equalToConstant:300).isActive=true
        for (i,name) in ["Red","Green","Blue"].enumerated() {
            let label=NSTextField(labelWithString:name)
            let slider=NSSlider(value:0,minValue:0,maxValue:255,target:self,action:#selector(slideRGB));slider.tag=i;slider.setAccessibilityLabel(name)
            slider.widthAnchor.constraint(equalToConstant:220).isActive=true
            let text=NSTextField(string:"");text.tag=i;text.target=self;text.action = #selector(typeRGB(_:));text.widthAnchor.constraint(equalToConstant:48).isActive=true
            sliders.append(slider);fields.append(text)
            let row=NSStackView(views:[label,slider,text]);row.spacing=12;slidersView.addArrangedSubview(row)
        }
        root.addArrangedSubview(slidersView);slidersView.isHidden=true
        alpha=NSSlider(value:1,minValue:0,maxValue:1,target:self,action:#selector(slideAlpha));alpha.widthAnchor.constraint(equalToConstant:206).isActive=true;alpha.setAccessibilityLabel("Opacity")
        opacityValue.widthAnchor.constraint(equalToConstant: 54).isActive = true
        opacityValue.setAccessibilityLabel("Opacity percent")
        opacityValue.target = self
        opacityValue.action = #selector(typeOpacity)
        root.addArrangedSubview(NSStackView(views:[NSTextField(labelWithString:"Opacity"),alpha, opacityValue]))
        hex=NSTextField(string:"");hex.target=self;hex.action = #selector(typeHex);hex.widthAnchor.constraint(equalToConstant:110).isActive=true;hex.setAccessibilityLabel("Hex color")
        let eyedropper=NSButton(image:NSImage(systemSymbolName:"eyedropper",accessibilityDescription:"Pick color from image")!,target:self,action:#selector(sample));eyedropper.bezelStyle = .rounded
        root.addArrangedSubview(NSStackView(views:[NSTextField(labelWithString:"Hex"),hex,eyedropper]))
        eyedropper.toolTip = "Pick from Image"
        let screen = NSButton(title: "Pick from Screen…", target: self, action: #selector(sampleScreen))
        screen.bezelStyle = .rounded
        let swatches = NSStackView()
        swatches.spacing = 10
        preview.isEnabled = false
        preview.widthAnchor.constraint(equalToConstant: 44).isActive = true
        swatches.addArrangedSubview(preview)
        for (index, value) in presets.enumerated() {
            let swatch = SwatchButton(color: NSColor(rgb: value))
            swatch.tag = index
            swatch.setAccessibilityLabel(["Black", "Blue", "Green", "Yellow", "Red"][index])
            swatch.widthAnchor.constraint(equalToConstant: 24).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 24).isActive = true
            swatch.target = self
            swatch.action = #selector(preset(_:))
            swatches.addArrangedSubview(swatch)
        }
        swatches.addArrangedSubview(screen)
        root.addArrangedSubview(swatches)
        refresh()
    }
    @objc private func sampleScreen() { NSColorSampler().show { [weak self] in if let color = $0 { self?.commit(InkColor(color)) } } }
    @objc private func preset(_ sender: NSButton) { commit(InkColor(rgb: presets[sender.tag])) }
    @objc private func typeOpacity() {
        let input = opacityValue.stringValue.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(input), percent.isFinite else { refresh(); return }
        commit(color.withUpdatedAlpha(max(0, min(100, percent)) / 100))
    }
    private func refresh() {
        field.color=color
        for (i,v) in [color.red,color.green,color.blue].enumerated() { sliders[i].doubleValue=v*255;fields[i].integerValue=Int((v*255).rounded()) }
        preview.color = color.ns
        opacityValue.stringValue = "\(Int((color.alpha * 100).rounded()))%"
        alpha.doubleValue=color.alpha
        hex.stringValue=String(format:"#%02X%02X%02X",Int((color.red*255).rounded()),Int((color.green*255).rounded()),Int((color.blue*255).rounded()))
    }
    private func commit(_ ink:InkColor) { color=ink;updated?(ink) }
    @objc private func selectMode(_ sender:NSSegmentedControl) { field.isHidden=sender.selectedSegment == 2;slidersView.isHidden=sender.selectedSegment != 2;field.mode=sender.selectedSegment }
    @objc private func slideRGB() { commit(InkColor(sliders[0].doubleValue/255,sliders[1].doubleValue/255,sliders[2].doubleValue/255,color.alpha)) }
    @objc private func typeRGB(_ sender:NSTextField) { sliders[sender.tag].doubleValue=Double(max(0,min(255,sender.integerValue)));slideRGB() }
    @objc private func slideAlpha() { commit(color.withUpdatedAlpha(alpha.doubleValue)) }
    @objc private func typeHex() {
        let input=hex.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"#",with:"")
        if input.count == 6,let value=UInt32(input,radix:16) { commit(InkColor(rgb:value).withUpdatedAlpha(CGFloat(color.alpha))) } else { refresh() }
    }
    @objc private func sample() { sampleImage?() }
}
