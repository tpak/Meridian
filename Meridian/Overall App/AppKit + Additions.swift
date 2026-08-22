// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa

extension NSFont {
    func size(for string: String, width: Double, attributes: [NSAttributedString.Key: AnyObject]) -> CGSize {
        let size = CGSize(width: width,
                          height: Double.greatestFiniteMagnitude)

        var otherAttributes: [NSAttributedString.Key: AnyObject] = [NSAttributedString.Key.font: self]

        attributes.forEach { arg in let (key, value) = arg; otherAttributes[key] = value }

        return NSString(string: string).boundingRect(with: size,
                                                     options: NSString.DrawingOptions.usesLineFragmentOrigin,
                                                     attributes: attributes).size
    }
}
