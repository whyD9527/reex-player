/// 把全角 ASCII（U+FF01–U+FF5E）转成半角（U+0021–U+007E）。
/// 中文输入法很容易把 ! : @ 等打成全角，SMB/FTP 认证会因此失败。
String toHalfWidth(String input) {
  final codes = input.codeUnits.map((c) {
    if (c >= 0xFF01 && c <= 0xFF5E) return c - 0xFEE0;
    if (c == 0x3000) return 0x20;
    return c;
  }).toList();
  return String.fromCharCodes(codes);
}
