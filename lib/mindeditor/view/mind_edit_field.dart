import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/controller/key_control.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_log/my_log.dart';
import '../document/paragraph_desc.dart';

class MindEditField extends StatefulWidget {
  final Controller controller;
  final bool isReadOnly;
  final FocusNode focusNode;
  final Document document;

  const MindEditField({
    Key? key,
    required this.controller,
    this.isReadOnly = false,
    required this.focusNode,
    required this.document,
  }): super(key: key);

  @override
  State<StatefulWidget> createState() => MindEditFieldState();
}

class MindEditFieldState extends State<MindEditField> implements TextInputClient {
  UniqueKey uniqueKey = UniqueKey();
  FocusAttachment? _focusAttachment;
  TextInputConnection? _textInputConnection;
  TextEditingValue? _lastEditingValue;

  bool get _hasFocus => widget.focusNode.hasFocus;
  bool get _hasConnection => _textInputConnection != null && _textInputConnection!.attached;
  bool get _shouldCreateInputConnection => kIsWeb || !widget.isReadOnly;

  @override
  void initState() {
    super.initState();
    initDocAndControlBlock();
    CallbackRegistry.registerEditFieldState(this);
    _attachFocus();
  }

  @override
  Widget build(BuildContext context) {
    MyLogger.debug('efantest: build block list');
    _focusAttachment!.reparent();
    Widget listView = _buildBlockList();
    if(Controller.instance.isDebugMode) {
      listView = Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey,
            width: 5,
          ),
        ),
        child: listView,
      );
    }
    var expanded = Expanded(
      child: listView,
    );
    return expanded;
  }

  @override
  void didUpdateWidget(MindEditField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      _focusAttachment?.detach();
      _attachFocus();
    }
    if(!_shouldCreateInputConnection) {
      _closeConnectionIfNeeded();
    } else {
      if(oldWidget.isReadOnly && _hasFocus) {
        _openConnectionIfNeeded();
      }
    }
  }

  @override
  void dispose() {
    _closeConnectionIfNeeded();
    widget.focusNode.removeListener(_handleFocusChanged);
    _focusAttachment!.detach();
    super.dispose();
  }

  void _attachFocus() {
    _focusAttachment = widget.focusNode.attach(
      context,
      onKey: _onFocusKey,
    );
    widget.focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    openOrCloseConnection();
    // _cursorCont.startOrStopCursorTimerIfNeeded(
    //     _hasFocus, widget.controller.selection);
    // _updateOrDisposeSelectionOverlayIfNeeded();
    if(_hasFocus) {
      // WidgetsBinding.instance!.addObserver(this);
      // _showCaretOnScreen();
    } else {
      // WidgetsBinding.instance!.removeObserver(this);
    }
    // updateKeepAlive();
  }

  // 按键会先在这里处理，如果返回ignored，再由系统处理
  KeyEventResult _onFocusKey(FocusNode node, RawKeyEvent _event) {
    MyLogger.debug('efantest: onFocusKey: event is $_event');
    if(_event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }
    RawKeyDownEvent evt = _event;
    final key = evt.logicalKey;
    var alt = evt.isAltPressed;
    var shift = evt.isShiftPressed;
    var ctrl = evt.isControlPressed;
    var meta = evt.isMetaPressed;
    var result = KeyboardControl.handleKeyDown(key, alt, ctrl, meta, shift);
    return result? KeyEventResult.handled: KeyEventResult.ignored;
  }

  void requestKeyboard() {
    if(_hasFocus) {
      _openConnectionIfNeeded();
      // _showCaretOnScreen();
    } else {
      widget.focusNode.requestFocus();
    }
  }
  void hideKeyboard() {
    if(!_hasFocus) {
      return;
    }
    widget.focusNode.unfocus();
    var block = widget.controller.getEditingBlockState()!;
    block.releaseCursor();
    widget.controller.clearEditingBlock();
  }

  void openOrCloseConnection() {
    if(widget.focusNode.hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openConnectionIfNeeded();
    } else if(!widget.focusNode.hasFocus) {
      _closeConnectionIfNeeded();
    }
  }

  void _openConnectionIfNeeded() {
    if(!_shouldCreateInputConnection) {
      return;
    }
    _lastEditingValue = widget.controller.getCurrentTextEditingValue();
    if(!_hasConnection) {
      _textInputConnection = TextInput.attach(
        this,
        TextInputConfiguration(
          inputType: TextInputType.multiline,
          readOnly: widget.isReadOnly,
          inputAction: TextInputAction.newline,
          enableSuggestions: !widget.isReadOnly,
          keyboardAppearance: Brightness.light,
        ),
      );
      // _textInputConnection!.updateConfig(const TextInputConfiguration(inputAction: TextInputAction.done));

      // _sentRemoteValues.add(_lastKnownRemoteTextEditingValue);
    }
    _textInputConnection!.setEditingState(_lastEditingValue!);
    _textInputConnection!.show();
  }

  void _closeConnectionIfNeeded() {
    if(!_hasConnection) {
      return;
    }
    _textInputConnection!.close();
    _textInputConnection = null;
    _lastEditingValue = null;
  }

  void refreshTextEditingValue() {
    if(!_hasConnection) {
      return;
    }
    _lastEditingValue = widget.controller.getCurrentTextEditingValue();
    MyLogger.debug('efantest: Refreshing editingValue to $_lastEditingValue');
    _textInputConnection!.setEditingState(_lastEditingValue!);
  }

  Widget _buildBlockList() {
    var builder = ListView.builder(
      itemCount: widget.document.paragraphs.length,
      itemBuilder: (context, index) {
        return _constructBlock(widget.document.paragraphs[index]);
      },
    );
    return builder;
  }

  Widget _constructBlock(ParagraphDesc para, {bool readOnly = false}) {
    Widget blockItem = _buildBlockFromDesc(para, readOnly);
    if(Controller.instance.isDebugMode) {
      blockItem = Container(
        child: blockItem,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blueGrey, width: 1),
        ),
      );
    }
    Widget containerWithPadding = Container(
      padding: const EdgeInsets.fromLTRB(0.0, 5.0, 0.0, 5.0),
      child: blockItem,
    );
    return containerWithPadding;
  }

  Widget _buildBlockFromDesc(ParagraphDesc paragraph, bool readOnly) {
    var view = MindEditBlock(
      texts: paragraph,
      controller: widget.controller,
      key: ValueKey(paragraph.getBlockId()),
      readOnly: readOnly,
    );
    return view;
  }

  List<Widget> getReadOnlyBlocks() {
    var result = <Widget>[];
    for(var para in widget.document.paragraphs) {
      var item = _constructBlock(para, readOnly: true);
      result.add(item);
    }
    return result;
  }

  @override
  void connectionClosed() {
    if(!_hasConnection) {
      return;
    }
    _textInputConnection!.connectionClosedReceived();
    _textInputConnection = null;
    // _lastKnownRemoteTextEditingValue = null;
    // _sentRemoteValues.clear();
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue {
    MyLogger.debug('efantest: currentTextEditingValue called');
    return _lastEditingValue;
  }

  @override
  void performAction(TextInputAction action) {
    MyLogger.debug('efantest: performAction: action=$action');
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    MyLogger.debug('efantest: performPrivateCommand');
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    MyLogger.debug('efantest: showAutocorrectionPromptRect');
  }

  TextEditingValue? getLastEditingValue() {
    return _lastEditingValue;
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    MyLogger.debug('efantest: updating editing value: $value, $_lastEditingValue');
    // 跟上一次没有区别，什么也不做
    if(_lastEditingValue == value) {
      return;
    }
    // 如果只是输入法的区别（composing改变），直接更新，不需要改变行为
    var sameText = _lastEditingValue!.text == value.text;
    if(sameText && _lastEditingValue!.selection == value.selection) {
      _lastEditingValue = value;
      return;
    }
    if(value.text.length > Controller.instance.setting.blockMaxCharacterLength) {
      // CallbackRegistry.unregisterCurrentSnackBar();
      CallbackRegistry.showSnackBar(
        SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('文字太长，超过${Controller.instance.setting.blockMaxCharacterLength}个字符'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2000),
        )
      );
      refreshTextEditingValue();
      return;
    }
    final oldEditingValue = _lastEditingValue!;
    _lastEditingValue = value;
    var controller = widget.controller;
    var currentBlock = controller.getEditingBlockState();
    currentBlock?.updateAndSaveText(oldEditingValue, value, sameText);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    MyLogger.debug('efantest: updateFloatingCursor');
  }

  @override
  void insertTextPlaceholder(Size size) {
    MyLogger.debug('efantest: insertTextPlaceholder');
  }

  @override
  void removeTextPlaceholder() {
    MyLogger.debug('efantest: removeTextPlaceholder');
  }

  @override
  void showToolbar() {
    MyLogger.debug('efantest: showToolbar');
  }

  void initDocAndControlBlock() {
    widget.document.clearEditingBlock();
    widget.document.clearTextSelection();
  }
  void refreshDoc({String? activeId, int position = 0}) {
    setState(() {
      initDocAndControlBlock();
      if(activeId != null) { // 如果提供了activeId，就将光标置于该id下的block首位
        var node = widget.document.getParagraph(activeId);
        node?.newTextSelection(position);
      }
    });
  }

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {
    // TODO: implement didChangeInputControl
    MyLogger.info('efantest didChangeInputControl() called');
  }

  @override
  void performSelector(String selectorName) {
    // TODO: implement performSelector
    MyLogger.info('efantest performSelector() called');
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    // TODO: implement insertContent
    MyLogger.info('efantest insertContent() called');
  }
}