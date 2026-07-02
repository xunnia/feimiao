/// 全局跟踪：当前是否有账单行的左滑操作面板处于打开/拖动状态。
///
/// 主页的「右滑开抽屉」手势据此让位——面板开着时，行上的右滑应该先把
/// 面板关回去（Slidable 自己处理），而不是同时把抽屉拉出来。
class SlidableTracker {
  SlidableTracker._();

  static final Set<Object> _open = <Object>{};

  /// 是否有任何一行的操作面板开着。
  static bool get anyOpen => _open.isNotEmpty;

  static void setOpen(Object key, bool open) {
    if (open) {
      _open.add(key);
    } else {
      _open.remove(key);
    }
  }
}
