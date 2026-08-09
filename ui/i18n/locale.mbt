///|
/// A browser UI language supported across LunaNexa's operator and developer
/// surfaces. Product-specific copy remains in the package that owns the view.
pub(all) enum Locale {
  English
  ChineseSimplified
} derive(Debug, Eq)

///|
pub fn default_locale() -> Locale {
  English
}

///|
pub fn Locale::storage_value(self : Locale) -> String {
  match self {
    English => "en"
    ChineseSimplified => "zh-CN"
  }
}

///|
pub fn Locale::language_tag(self : Locale) -> String {
  self.storage_value()
}

///|
pub fn Locale::label(self : Locale) -> String {
  match self {
    English => "English"
    ChineseSimplified => "简体中文"
  }
}

///|
pub fn Locale::is_chinese(self : Locale) -> Bool {
  self == ChineseSimplified
}

///|
pub fn Locale::alternate(self : Locale) -> Locale {
  match self {
    English => ChineseSimplified
    ChineseSimplified => English
  }
}

///|
/// Parses the stable browser preference value. Unknown or obsolete values fail
/// safely to English so a damaged preference can never block either UI.
pub fn parse_locale(value : String) -> Locale {
  match value.trim().to_lower() {
    "zh" | "zh-cn" | "zh_hans" | "zh-hans" => ChineseSimplified
    _ => English
  }
}
