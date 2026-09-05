use irondash_message_channel::IsolateId;

/// Identifies one Flutter view inside one Dart isolate.
///
/// `native_window_handle` is transport data used while constructing the
/// platform context. Logical identity is still isolate + view ID.
#[derive(Debug, Clone, Copy)]
pub struct PlatformViewContextId {
    pub isolate_id: IsolateId,
    pub view_id: i64,
    pub native_window_handle: Option<i64>,
}

impl PlatformViewContextId {
    pub fn new(isolate_id: IsolateId, view_id: i64, native_window_handle: Option<i64>) -> Self {
        Self {
            isolate_id,
            view_id,
            native_window_handle,
        }
    }
}

impl PartialEq for PlatformViewContextId {
    fn eq(&self, other: &Self) -> bool {
        self.isolate_id == other.isolate_id && self.view_id == other.view_id
    }
}

impl Eq for PlatformViewContextId {}

impl std::hash::Hash for PlatformViewContextId {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.isolate_id.hash(state);
        self.view_id.hash(state);
    }
}
