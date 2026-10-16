import Foundation

extension String {
    /// Only the decimal digits of the string, each converted to its ASCII
    /// `0`–`9` form.
    ///
    /// Phone numbers and OTP codes are sent to the server and compared as
    /// ASCII, but `Character.isNumber` also accepts Devanagari, Arabic-Indic and
    /// other scripts' digits — and the number pad types those when the app or
    /// device language is Hindi etc. (`१०६२९`). Filter through this instead of
    /// `isNumber` anywhere a numeric input is read.
    var asciiDigits: String {
        var result = ""
        for character in self {
            guard character.isASCII else {
                if let digit = character.decimalDigitValue {
                    result.append(Character(String(digit)))
                }
                continue
            }
            if character.isWholeNumber { result.append(character) }
        }
        return result
    }
}

private extension Character {
    /// 0–9 for any Unicode decimal digit (`Nd`), `nil` for everything else
    /// (fractions, roman numerals, superscripts, letters).
    var decimalDigitValue: Int? {
        guard unicodeScalars.count == 1,
              let scalar = unicodeScalars.first,
              scalar.properties.numericType == .decimal,
              let value = scalar.properties.numericValue
        else { return nil }
        return Int(value)
    }
}
