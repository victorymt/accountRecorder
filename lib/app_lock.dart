class AppLock {
  AppLock._();

  /// 系统文件选择器等系统界面打开期间为 true，抑制切后台自动锁定。
  static bool pickerActive = false;
}
