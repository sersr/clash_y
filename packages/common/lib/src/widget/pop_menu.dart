import 'package:common/src/navigator_observer.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:material_ui/material_ui.dart';

class PopMenuController {
  static PopMenuController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PopMenuControllerScope>()
        ?.controller;
  }

  final menuIsShowing = false.al;
  final AV<Offset?> tapOffset = .val(null);

  late final listenable = Listenable.merge([menuIsShowing, tapOffset]);

  void showMenu({Offset? offset}) {
    tapOffset.value = offset;
    menuIsShowing.value = true;
  }

  void hideMenu() {
    tapOffset.value = null;
    menuIsShowing.value = false;
  }

  void toggleMenu({Offset? offset}) {
    tapOffset.value = offset;
    menuIsShowing.value = !menuIsShowing.value;
  }
}

class PopMenuControllerScope extends InheritedWidget {
  const PopMenuControllerScope({
    super.key,
    required super.child,
    required this.controller,
  });
  final PopMenuController controller;
  @override
  bool updateShouldNotify(covariant PopMenuControllerScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

class PopMenu extends StatefulWidget {
  const PopMenu({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.barrierColor = Colors.black12,
    this.margin = const .all(10),
    this.menuOnChange,
  });

  final Widget child;
  final Color barrierColor;
  final EdgeInsets margin;
  final Widget Function() menuBuilder;
  final void Function(bool)? menuOnChange;

  @override
  State<PopMenu> createState() => _PopMenuState();
}

class _PopMenuState extends State<PopMenu> {
  late PopMenuController _controller;

  void _showMenu() {
    controller.show();
  }

  void _hideMenu() {
    controller.hide();
  }

  void _updateView() {
    bool menuIsShowing = _controller.menuIsShowing.value;
    widget.menuOnChange?.call(menuIsShowing);
    if (menuIsShowing) {
      _showMenu();
    } else {
      _hideMenu();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = PopMenuController();
    _controller.listenable.addListener(_updateView);
  }

  @override
  void dispose() {
    _hideMenu();
    _controller.listenable.removeListener(_updateView);
    super.dispose();
  }

  final controller = OverlayPortalController();
  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: controller,
      overlayChildBuilder: overlayChildBuilder,
      child: widget.child,
    );
  }

  final childKey = GlobalKey();
  Widget overlayChildBuilder(BuildContext context) {
    final view = View.of(context);
    final viewInsets = EdgeInsets.fromViewPadding(
      view.viewInsets,
      view.devicePixelRatio,
    );

    final box = context.findRenderObject() as RenderBox;

    var keyboardHeight = viewInsets.bottom;
    final width = Nav.screenWidth;

    return Cs(() {
      Widget menu = Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: width, minWidth: 0),
          child: CustomMultiChildLayout(
            key: childKey,
            delegate: _MenuLayoutDelegate(
              anchorSize: box.size,
              anchorOffset: box.localToGlobal(.zero),
              keyboardHeight: keyboardHeight,
              margin: widget.margin,
              offset: _controller.tapOffset.value,
            ),
            children: <Widget>[
              LayoutId(
                id: _MenuLayoutDelegate.content,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Material(
                      color: Colors.transparent,
                      child: widget.menuBuilder(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      return PopMenuControllerScope(
        controller: _controller,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent event) {
            Offset offset = event.localPosition;
            final child =
                childKey.currentContext?.findRenderObject() as RenderBox?;
            if (child == null) return;
            final childOffset = child.localToGlobal(Offset.zero);
            final rect = childOffset & child.size;

            if (rect.contains(offset)) {
              return;
            }
            _controller.hideMenu();
          },
          child: widget.barrierColor == Colors.transparent
              ? menu
              : Container(color: widget.barrierColor, child: menu),
        ),
      );
    });
  }
}

class _MenuLayoutDelegate extends MultiChildLayoutDelegate {
  _MenuLayoutDelegate({
    required this.anchorSize,
    required this.anchorOffset,
    required this.keyboardHeight,
    required this.margin,
    this.offset,
  });

  static const content = 'content';

  final Size anchorSize;
  final Offset anchorOffset;
  final double keyboardHeight;
  final Offset? offset;

  final EdgeInsets margin;
  @override
  void performLayout(Size size) {
    final childSize = Size(
      size.width - margin.horizontal,
      size.height - margin.vertical,
    );

    if (hasChild(content)) {
      final contentSize = layoutChild(content, BoxConstraints.loose(childSize));
      var dx = anchorOffset.dx;
      var dy = anchorOffset.dy + anchorSize.height;

      if (dx + contentSize.width > childSize.width) {
        dx = size.width - childSize.width;
      }

      if (dy + contentSize.height > childSize.height) {
        dy = size.height - childSize.height;
      }
      positionChild(content, .new(dx, dy));
    }
  }

  @override
  bool shouldRelayout(MultiChildLayoutDelegate oldDelegate) => false;
}
