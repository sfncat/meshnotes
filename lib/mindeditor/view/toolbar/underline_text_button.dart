import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/switch_button_state.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../../document/paragraph_desc.dart';
import 'appearance_setting.dart';

class UnderlineTextButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const UnderlineTextButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ToolbarSwitchButton(
      icon: Icon(Icons.format_underline, size: appearance.iconSize),
      appearance: appearance,
      controller: controller,
      tip: 'Underline',
      initCallback: (Function(bool) _setOn) {
        CallbackRegistry.registerSelectionChangedWatcher('underline', (TextSpansStyle? style) {
          if(style == null) {
            MyLogger.debug('efantest: style is null');
            _setOn(false);
            return;
          }
          if(style.isAllUnderline) {
            MyLogger.debug('efantest: underline is on');
            _setOn(true);
          } else {
            MyLogger.debug('efantest: underline is off');
            _setOn(false);
          }
        });
      },
      destroyCallback: () {
        CallbackRegistry.unregisterDocumentChangedWatcher('underline');
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        var isUnderline = blockState?.triggerSelectedUnderline();
        CallbackRegistry.requestFocus();
        return isUnderline?? false;
      },
    );
  }
}
