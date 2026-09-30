import 'dart:js_interop';

@JS('athleteSaveBeforeUpdate')
external set _saveBeforeUpdate(JSFunction callback);

void registerUpdateSave(Future<void> Function() save) {
  _saveBeforeUpdate = (() => save().then<JSAny?>((_) => null).toJS).toJS;
}
