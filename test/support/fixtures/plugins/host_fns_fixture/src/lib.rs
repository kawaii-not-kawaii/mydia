//! Host-function test fixture (U2/U4) — see Cargo.toml for the behavior table.
//!
//! Exercises the typed mydia:plugin/host imports through the SDK's generated
//! bindings, so it validates the host-import callback protocol end to end.
//! Each branch is keyed by event type; structured params ride in the event's
//! `metadata-json` and are pulled out with tinyjson.

use mydia_plugin_sdk::host;
use mydia_plugin_sdk::types::{
    DataRequest, Event, ListRequest, OutboundRequest, ReadResult, ScheduleTick,
};
use std::collections::HashMap;
use tinyjson::JsonValue;

fn meta(evt: &Event) -> HashMap<String, JsonValue> {
    match evt.metadata_json.parse::<JsonValue>() {
        Ok(JsonValue::Object(map)) => map,
        _ => HashMap::new(),
    }
}

fn str_field(map: &HashMap<String, JsonValue>, key: &str) -> Option<String> {
    match map.get(key) {
        Some(JsonValue::String(s)) => Some(s.clone()),
        _ => None,
    }
}

fn i64_field(map: &HashMap<String, JsonValue>, key: &str) -> Option<i64> {
    match map.get(key) {
        Some(JsonValue::Number(n)) => Some(*n as i64),
        _ => None,
    }
}

fn u32_field(map: &HashMap<String, JsonValue>, key: &str) -> Option<u32> {
    i64_field(map, key).map(|n| n as u32)
}

#[mydia_plugin_sdk::plugin(on_schedule = on_schedule)]
fn on_event(evt: Event) -> Result<String, String> {
    let m = meta(&evt);

    match evt.event.as_str() {
        "log" => {
            host::log("info", "hello from guest");
            Ok("{\"logged\":true}".to_string())
        }

        "http" => {
            let req = OutboundRequest {
                url: "https://example.test/hook".to_string(),
                method: "POST".to_string(),
                headers: vec![("content-type".to_string(), "application/json".to_string())],
                body: Some("{\"x\":1}".to_string()),
            };

            match host::http_request(&req) {
                Ok(resp) => Ok(format!("{{\"status\":{},\"ok\":{}}}", resp.status, resp.ok)),
                Err(e) => Err(format!("http error: {:?}", e)),
            }
        }

        "data" => {
            let id = evt.resource_id.clone().unwrap_or_default();
            let req = DataRequest {
                namespace: "media_item".to_string(),
                id,
            };

            match host::data_read(&req) {
                Ok(ReadResult::MediaItem(item)) => Ok(format!("{{\"title\":{:?}}}", item.title)),
                Err(e) => Err(format!("data error: {:?}", e)),
            }
        }

        "kv-set" => {
            let key = str_field(&m, "key").unwrap_or_default();
            let value = str_field(&m, "value").unwrap_or_default();
            match host::kv_set(&key, &value) {
                Ok(_) => Ok("{\"ok\":true}".to_string()),
                Err(e) => Err(format!("kv-set error: {:?}", e)),
            }
        }

        "kv-get" => {
            let key = str_field(&m, "key").unwrap_or_default();
            match host::kv_get(&key) {
                Ok(Some(v)) => Ok(format!("{{\"found\":true,\"value\":{:?}}}", v)),
                Ok(None) => Ok("{\"found\":false}".to_string()),
                Err(e) => Err(format!("kv-get error: {:?}", e)),
            }
        }

        "kv-delete" => {
            let key = str_field(&m, "key").unwrap_or_default();
            match host::kv_delete(&key) {
                Ok(_) => Ok("{\"ok\":true}".to_string()),
                Err(e) => Err(format!("kv-delete error: {:?}", e)),
            }
        }

        "data-list" => {
            let req = ListRequest {
                namespace: str_field(&m, "namespace").unwrap_or_else(|| "media_item".to_string()),
                cursor: str_field(&m, "cursor"),
                updated_since: str_field(&m, "updated_since"),
                limit: u32_field(&m, "limit"),
            };

            match host::data_list(&req) {
                Ok(result) => {
                    let has_next = result.next_cursor.is_some();
                    Ok(format!(
                        "{{\"count\":{},\"has_next\":{}}}",
                        result.items.len(),
                        has_next
                    ))
                }
                Err(e) => Err(format!("data-list error: {:?}", e)),
            }
        }

        "connections-list" => match host::connections_list() {
            Ok(conns) => {
                let ids: Vec<String> = conns.iter().map(|c| format!("{:?}", c.user_id)).collect();
                Ok(format!(
                    "{{\"count\":{},\"user_ids\":[{}]}}",
                    conns.len(),
                    ids.join(",")
                ))
            }
            Err(e) => Err(format!("connections-list error: {:?}", e)),
        },

        "connection-request" => {
            let id = str_field(&m, "connection_id").unwrap_or_default();
            let req = OutboundRequest {
                url: str_field(&m, "url").unwrap_or_default(),
                method: "GET".to_string(),
                headers: vec![],
                body: None,
            };

            match host::connection_request(&id, &req) {
                Ok(resp) => Ok(format!("{{\"status\":{},\"ok\":{}}}", resp.status, resp.ok)),
                Err(e) => Err(format!("connection-request error: {:?}", e)),
            }
        }

        _ => Ok("{}".to_string()),
    }
}

fn on_schedule(tick: ScheduleTick) -> Result<String, String> {
    Ok(format!(
        "{{\"scheduled\":true,\"slug\":{:?},\"now\":{}}}",
        tick.slug, tick.now
    ))
}
