import Foundation

extension Data {
    /// Tencent's quote API returns GBK-encoded text; decode it as GB18030 (a superset of GBK)
    func decodedGB18030() -> String? {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        return String(data: self, encoding: encoding)
    }
}
