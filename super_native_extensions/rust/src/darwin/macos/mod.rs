mod clipboard_events;
mod data_provider;
mod drag;
mod drag_common;
mod drop;
mod hot_key;
mod hot_key_sys;
mod keyboard_layout;
mod keyboard_layout_sys;
mod menu;
mod reader;
mod util;

use irondash_engine_context::EngineContext;
use objc2::{rc::Id, ClassType};
use objc2_app_kit::{NSView, NSWindow};

use crate::{
    error::{NativeExtensionsError, NativeExtensionsResult},
    view_context::PlatformViewContextId,
};

fn flutter_view_for_context(
    id: PlatformViewContextId,
    engine_handle: i64,
) -> NativeExtensionsResult<Id<NSView>> {
    if let Some(window_handle) = id.native_window_handle.filter(|handle| *handle != 0) {
        let window = unsafe { Id::retain(window_handle as *mut NSWindow) }.ok_or_else(|| {
            NativeExtensionsError::OtherError("invalid native window handle".into())
        })?;
        let content_view = window.contentView().ok_or_else(|| {
            NativeExtensionsError::OtherError("native window has no content view".into())
        })?;
        find_flutter_view(&content_view).ok_or_else(|| {
            NativeExtensionsError::OtherError("native window has no FlutterView".into())
        })
    } else {
        let view = EngineContext::get()?.get_flutter_view(engine_handle)?;
        Ok(unsafe { Id::cast(view) })
    }
}

fn find_flutter_view(view: &NSView) -> Option<Id<NSView>> {
    if view.class().name() == "FlutterView" {
        return Some(view.retain());
    }
    let subviews = unsafe { view.subviews() };
    for index in 0..subviews.count() {
        let subview = unsafe { subviews.objectAtIndex(index) };
        if let Some(view) = find_flutter_view(&subview) {
            return Some(view);
        }
    }
    None
}

pub use clipboard_events::*;
pub use data_provider::*;
pub use drag::*;
pub use drop::*;
pub use hot_key::*;
pub use keyboard_layout::*;
pub use menu::*;
pub use reader::*;
