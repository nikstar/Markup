// AppKit port of the static-image controls in TextSettingsComponent.swift.
// Font menu values from DrawingScreen.swift; original style icon assets.
// Copyright Telegram Messenger. GNU GPL v2 or later.
import AppKit

let telegramTextFonts:[(name:String,title:String)]=[
    (NSFont.systemFont(ofSize:48,weight:.semibold).fontName,"San Francisco"),
    ("AmericanTypewriter","Typewriter"),("AvenirNext-DemiBoldItalic","Avenir Next"),
    ("CourierNewPS-BoldMT","Courier New"),("Noteworthy-Bold","Noteworthy"),
    ("Georgia-Bold","Georgia"),("Papyrus","Papyrus"),("SnellRoundhand-Bold","Snell Roundhand")
]
final class TelegramTextSettings:NSStackView {
    var onStyle:((TextStyle)->Void)?;var onAlignment:((TextAlignment)->Void)?;var onFont:((String)->Void)?
    var onEdit:(()->Void)?
    private var icons: [String: NSImage] = [:]
    private let editButton = NSButton()
    private let cancelButton = NSButton()
    var onCancel: (() -> Void)?
    var isEditing = false {
        didSet {
            editButton.title = isEditing ? "Done" : "Edit Text"
            cancelButton.isHidden = !isEditing
        }
    }
    private var style=TextStyle.regular,textAlignment=TextAlignment.center
    private let styleButton=NSButton(),alignmentButton=TelegramTextAlignmentButton(),fontButton=NSPopUpButton()
    override init(frame:NSRect) {
        super.init(frame:frame)
        orientation = .vertical
        spacing = 3
        alignment = .centerX
        let formatting = NSStackView()
        formatting.spacing = 5
        formatting.alignment = .centerY
        addArrangedSubview(formatting)
        let actions = NSStackView()
        actions.spacing = 5
        addArrangedSubview(actions)
        styleButton.target=self;styleButton.action = #selector(toggleStyle);styleButton.isBordered=false;styleButton.imagePosition = .imageOnly;styleButton.setAccessibilityIdentifier("textStyle")
        styleButton.widthAnchor.constraint(equalToConstant:32).isActive=true;styleButton.heightAnchor.constraint(equalToConstant:32).isActive=true;formatting.addArrangedSubview(styleButton)
        alignmentButton.target=self;alignmentButton.action = #selector(toggleAlignment);alignmentButton.isBordered=false;alignmentButton.widthAnchor.constraint(equalToConstant:32).isActive=true;alignmentButton.heightAnchor.constraint(equalToConstant:32).isActive=true;formatting.addArrangedSubview(alignmentButton)
        for font in telegramTextFonts {
            fontButton.addItem(withTitle:font.title)
            fontButton.lastItem?.attributedTitle=NSAttributedString(string:font.title,attributes:[.font:NSFont(name:font.name,size:17) ?? .systemFont(ofSize:17,weight:.semibold)])
        }
        fontButton.target=self;fontButton.action = #selector(selectFont);fontButton.widthAnchor.constraint(equalToConstant:152).isActive=true;formatting.addArrangedSubview(fontButton)
        cancelButton.title = "Cancel"
        cancelButton.action = #selector(cancel)
        cancelButton.target = self
        cancelButton.bezelStyle = .rounded
        actions.addArrangedSubview(cancelButton)
        editButton.target = self
        editButton.action = #selector(edit)
        editButton.bezelStyle = .rounded
        editButton.setAccessibilityIdentifier("applyText")
        actions.addArrangedSubview(editButton)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(style:TextStyle,alignment:TextAlignment,font:String) {
        self.style=style;self.textAlignment=alignment;alignmentButton.textAlignment=alignment
        let name=style == .regular ? "TextDefault" : style == .filled ? "TextFilled" : style == .semi ? "TextSemi" : "TextStroke"
        if icons[name] == nil, let url = Bundle(for: Self.self).url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = CGSize(width: 30, height: 30)
            icons[name] = image
        }
        styleButton.image = icons[name]
        styleButton.setAccessibilityLabel("Text style: "+style.rawValue)
        if fontButton.numberOfItems > telegramTextFonts.count { fontButton.removeItem(at: telegramTextFonts.count) }
        if let i = telegramTextFonts.firstIndex(where: { $0.name == font }) {
            fontButton.selectItem(at: i)
        } else {
            fontButton.addItem(withTitle: NSFont(name: font, size: 17)?.displayName ?? font)
            fontButton.lastItem?.representedObject = font
            fontButton.selectItem(at: telegramTextFonts.count)
        }
    }
    @objc private func toggleStyle() {
        let next:TextStyle
        switch style { case .regular:next = .filled;case .filled:next = .semi;case .semi:next = .stroke;case .stroke,.blur:next = .regular }
        onStyle?(next)
    }
    @objc private func toggleAlignment() { onAlignment?(textAlignment == .left ? .center : textAlignment == .center ? .right : .left) }
    @objc private func selectFont() { if let custom = fontButton.selectedItem?.representedObject as? String { onFont?(custom) }
        else { onFont?(telegramTextFonts[fontButton.indexOfSelectedItem].name) } }
    @objc private func cancel() { onCancel?() }
    @objc private func edit() { onEdit?() }
}
private final class TelegramTextAlignmentButton:NSButton {
    var textAlignment=TextAlignment.center { didSet { needsDisplay=true;setAccessibilityLabel("Text alignment: "+textAlignment.rawValue) } }
    override var isFlipped:Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        // TextAlignmentComponent: four 1.5 pt lines, 3.5 pt gaps, lengths 21 and 13.
        NSColor.labelColor.setFill()
        for i in 0..<4 {
            let length:CGFloat=i%2 == 0 ? 21 : 13
            let x:CGFloat=textAlignment == .left ? 0 : textAlignment == .right ? 21-length : (21-length)/2
            NSBezierPath(roundedRect:CGRect(x:(bounds.width-21)/2+x,y:(bounds.height-18)/2+CGFloat(i)*5,width:length,height:1.5),xRadius:1,yRadius:1).fill()
        }
    }
}
