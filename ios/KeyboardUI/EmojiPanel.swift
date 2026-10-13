import SwiftUI
import UIKit

/// The emoji page, in place of the keys: a scrolling grid of emoji by
/// category, recent ones first, and a bar along the bottom with ABC, the
/// categories and delete, as on Apple's emoji keyboard. A keyboard cannot
/// open Apple's own, so this is ours.
///
/// It is UIKit and reads raw touches, as the keys do, rather than SwiftUI
/// buttons: buttons wait for iOS to rule out its own edge gestures, which
/// along the bottom of the screen made the bar slow, and a scroll view holds
/// a button's press back to see if it is a scroll.
struct EmojiPanel: UIViewRepresentable {
    let model: KeyboardModel

    func makeUIView(context: Context) -> EmojiPanelView {
        EmojiPanelView(model: model)
    }

    /// Recent emoji are read once, when the page opens, so the grid does not
    /// shift under the finger while typing, as in iOS.
    func updateUIView(_ view: EmojiPanelView, context: Context) {}
}

final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegate,
                            UICollectionViewDelegateFlowLayout {
    private let model: KeyboardModel
    private let sections: [EmojiData.Category]
    private let grid: UICollectionView
    private let bar: EmojiBar

    private static let barHeight: CGFloat = 40
    private static let cellHeight: CGFloat = 42

    init(model: KeyboardModel) {
        self.model = model
        let recent = model.recentEmoji.isEmpty ? [] :
            [EmojiData.Category(id: "Frequently used", symbol: "clock", emoji: model.recentEmoji)]
        sections = recent + EmojiData.categories

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.headerReferenceSize = CGSize(width: 0, height: 26)
        grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
        bar = EmojiBar(symbols: sections.map(\.symbol), names: sections.map(\.id))
        super.init(frame: .zero)

        grid.backgroundColor = .clear
        grid.showsVerticalScrollIndicator = false
        grid.allowsSelection = false
        // A touch shows straight away; a scroll still cancels it.
        grid.delaysContentTouches = false
        grid.dataSource = self
        grid.delegate = self
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")
        grid.register(EmojiHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                      withReuseIdentifier: "header")
        grid.contentInset = UIEdgeInsets(top: 0, left: 4, bottom: 4, right: 4)
        addSubview(grid)

        bar.onLetters = { [weak model] in model?.page = .letters }
        bar.onCategory = { [weak self] index in self?.jump(to: index) }
        bar.onDelete = { [weak model] in model?.perform(.backspace) }
        addSubview(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barHeight = min(Self.barHeight, bounds.height * 0.22)
        let gridFrame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barHeight)
        if grid.frame.size != gridFrame.size { grid.collectionViewLayout.invalidateLayout() }
        grid.frame = gridFrame
        bar.frame = CGRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)
    }

    /// Straight to a category's heading, without animation, as in iOS.
    private func jump(to section: Int) {
        grid.layoutIfNeeded()
        guard let header = grid.layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: section)) else { return }
        let bottom = max(grid.contentSize.height - grid.bounds.height + grid.contentInset.bottom, 0)
        grid.setContentOffset(CGPoint(x: grid.contentOffset.x, y: min(header.frame.minY, bottom)), animated: false)
        bar.selected = section
    }

    // MARK: - Grid

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].emoji.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as! EmojiCell
        let emoji = sections[indexPath.section].emoji[indexPath.item]
        cell.emoji = emoji
        cell.onTap = { [weak model] in model?.insertEmoji(emoji) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! EmojiHeader
        header.label.text = sections[indexPath.section].id.uppercased()
        return header
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width - collectionView.contentInset.left - collectionView.contentInset.right
        let columns = max(1, (width / 42).rounded(.down))
        return CGSize(width: (width / columns).rounded(.down), height: Self.cellHeight)
    }

    /// The bar follows the scrolling, lighting the category in view.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let top = scrollView.contentOffset.y + 30
        let visible = grid.indexPathsForVisibleItems.filter {
            (grid.layoutAttributesForItem(at: $0)?.frame.maxY ?? 0) > top
        }
        if let section = visible.map(\.section).min(), bar.selected != section { bar.selected = section }
    }
}

/// One emoji. It lights at once on touch and types on lift; a scroll that
/// starts on it cancels the touch instead.
private final class EmojiCell: UICollectionViewCell {
    private let label = UILabel()
    var onTap: (() -> Void)?
    var emoji = "" {
        didSet {
            label.text = emoji
            accessibilityLabel = emoji
            accessibilityIdentifier = emoji
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 31)
        label.textAlignment = .center
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = [.keyboardKey]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.backgroundColor = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        contentView.backgroundColor = EmojiColors.pressed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        contentView.backgroundColor = nil
        guard let touch = touches.first, bounds.insetBy(dx: -8, dy: -8).contains(touch.location(in: self)) else { return }
        UIDevice.current.playInputClick()
        onTap?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        contentView.backgroundColor = nil
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }
}

private final class EmojiHeader: UICollectionReusableView {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = EmojiColors.text
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 8, dy: 0)
    }
}

/// ABC, the categories and delete. One view takes every touch and acts as
/// the finger lands, as the keyboard's page keys do; delete repeats while held.
private final class EmojiBar: UIView {
    var onLetters: (() -> Void)?
    var onCategory: ((Int) -> Void)?
    var onDelete: (() -> Void)?
    var selected = 0 { didSet { if selected != oldValue { updateIcons() } } }

    private let letters = EmojiBar.keyView()
    private let delete = EmojiBar.keyView()
    private var icons: [UIImageView] = []
    private let highlight = UIView()
    private var timer: Timer?

    private static let keyWidth: CGFloat = 46

    init(symbols: [String], names: [String]) {
        super.init(frame: .zero)
        isMultipleTouchEnabled = false

        let abc = UILabel()
        abc.text = "ABC"
        abc.font = .systemFont(ofSize: 15, weight: .medium)
        abc.textAlignment = .center
        abc.textColor = .label
        letters.addSubview(abc)
        letters.accessibilityLabel = "letters"
        addSubview(letters)

        highlight.backgroundColor = EmojiColors.pressed.withAlphaComponent(0.7)
        highlight.layer.cornerRadius = 15
        addSubview(highlight)

        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        for (symbol, name) in zip(symbols, names) {
            let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: config))
            icon.contentMode = .center
            icon.isAccessibilityElement = true
            icon.accessibilityLabel = name
            icon.accessibilityTraits = .button
            icons.append(icon)
            addSubview(icon)
        }

        let glyph = UIImageView(image: UIImage(systemName: "delete.left",
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)))
        glyph.contentMode = .center
        glyph.tintColor = .label
        delete.addSubview(glyph)
        delete.accessibilityLabel = "delete"
        addSubview(delete)
        updateIcons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func keyView() -> UIView {
        let view = UIView()
        view.backgroundColor = EmojiColors.key
        view.layer.cornerRadius = Metrics.cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.15
        view.layer.shadowRadius = 0
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.isAccessibilityElement = true
        view.accessibilityTraits = .keyboardKey
        return view
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let margin = Metrics.sideMargin, keyHeight = min(32, bounds.height - 6)
        let y = (bounds.height - keyHeight) / 2
        letters.frame = CGRect(x: margin, y: y, width: Self.keyWidth, height: keyHeight)
        delete.frame = CGRect(x: bounds.width - margin - Self.keyWidth, y: y, width: Self.keyWidth, height: keyHeight)
        letters.subviews.first?.frame = letters.bounds
        delete.subviews.first?.frame = delete.bounds
        let start = letters.frame.maxX + 4, end = delete.frame.minX - 4
        let width = (end - start) / CGFloat(max(icons.count, 1))
        for (index, icon) in icons.enumerated() {
            icon.frame = CGRect(x: start + width * CGFloat(index), y: 0, width: width, height: bounds.height)
        }
        updateIcons()
    }

    private func updateIcons() {
        for (index, icon) in icons.enumerated() {
            icon.tintColor = index == selected ? .label : EmojiColors.text
        }
        if icons.indices.contains(selected) {
            highlight.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
            highlight.center = icons[selected].center
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let x = touches.first?.location(in: self).x else { return }
        UIDevice.current.playInputClick()
        if x < letters.frame.maxX + 2 {
            letters.backgroundColor = EmojiColors.pressed
            onLetters?()
        } else if x > delete.frame.minX - 2 {
            delete.backgroundColor = EmojiColors.pressed
            onDelete?()
            scheduleDelete(after: 0.45)
        } else if let index = icons.firstIndex(where: { x < $0.frame.maxX }) ?? icons.indices.last {
            selected = index
            onCategory?(index)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release() }

    private func release() {
        timer?.invalidate()
        timer = nil
        letters.backgroundColor = EmojiColors.key
        delete.backgroundColor = EmojiColors.key
    }

    /// Delete repeats while held, as the keyboard's does.
    private func scheduleDelete(after delay: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.timer != nil else { return }
                self.onDelete?()
                self.scheduleDelete(after: 0.09)
            }
        }
    }
}

/// The keyboard's colours, as UIKit colours that follow light and dark.
private enum EmojiColors {
    static let key = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 61 / 255, alpha: 1) : .white }
    static let pressed = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.40, alpha: 1) : UIColor(red: 0.74, green: 0.76, blue: 0.79, alpha: 1) }
    static let text = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 172 / 255, alpha: 1) : UIColor(red: 54 / 255, green: 56 / 255, blue: 60 / 255, alpha: 1) }
}
