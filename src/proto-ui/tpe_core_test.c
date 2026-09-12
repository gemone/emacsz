#include "tpe_core.h"

#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

typedef struct TestHost {
  ProtoUiTerminalGroupV1 terminal;
  ProtoUiFrameGroupV1 frame;
  ProtoUiRedisplayGroupV1 redisplay;
  ProtoUiInputGroupV1 input;
  ProtoUiLifecycleGroupV1 lifecycle;
  uint64_t next_terminal_id;
  ProtoUiIdentity live;
} TestHost;

static ProtoUiPureRuntimeStatus ok_identity(void *context, const ProtoUiIdentity *value) {
  (void)context;
  return value != NULL && value->id != 0 && value->generation != 0
             ? PROTO_UI_RUNTIME_OK : PROTO_UI_RUNTIME_INVALID;
}

static ProtoUiPureRuntimeStatus ok_void(void *context) { (void)context; return PROTO_UI_RUNTIME_OK; }

static ProtoUiPureRuntimeStatus fake_register(void *context, const ProtoUiIdentity *host, ProtoUiIdentity *value) {
  (void)context; (void)host; memset(value, 0, sizeof(*value)); value->id = 91; value->generation = 1; return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus fake_state(void *context, const ProtoUiIdentity *value, ProtoUiFrameState *state) {
  (void)context; (void)value; memset(state, 0, sizeof(*state)); state->generation = 1; state->focused = 1; return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus fake_geometry(void *context, const ProtoUiIdentity *value, ProtoUiGeometry *geometry) {
  (void)context; (void)value; memset(geometry, 0, sizeof(*geometry)); geometry->width = 80; geometry->height = 24; return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus fake_capture(void *context, const ProtoUiCaptureRequest *request, ProtoUiIdentity *value) {
  (void)context; (void)request; memset(value, 0, sizeof(*value)); value->id = 81; value->generation = 1; return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus fake_capture_identity(void *context, const ProtoUiIdentity *session, const void *record) {
  (void)context; (void)record;
  return session != NULL && session->id == 81 ? PROTO_UI_RUNTIME_OK : PROTO_UI_RUNTIME_INVALID;
}

static ProtoUiPureRuntimeStatus fake_deliver(void *context, const ProtoUiInputEvent *event, ProtoUiInputAck *ack) {
  (void)context; memset(ack, 0, sizeof(*ack)); ack->event_id = event->event_id; ack->accepted = true; return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus fake_result(void *context, const ProtoUiInputResult *result) {
  (void)context; return result->event_id != 0 ? PROTO_UI_RUNTIME_OK : PROTO_UI_RUNTIME_INVALID;
}

static ProtoUiPureRuntimeStatus fake_completion(void *context, const ProtoUiCompletionStatus *result) {
  (void)context; return result->transaction_id != 0 ? PROTO_UI_RUNTIME_OK : PROTO_UI_RUNTIME_INVALID;
}

static ProtoUiPureRuntimeStatus fake_heartbeat(void *context, ProtoUiHeartbeatResult *result) {
  (void)context; memset(result, 0, sizeof(*result)); result->healthy = true; return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus fake_diagnostic(void *context, const ProtoUiDiagnosticRecord *record) {
  (void)context; (void)record; return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus fake_create(void *context, const ProtoUiTerminalCreateRequest *request, ProtoUiIdentity *result) {
  TestHost *host = context;
  if (request->kind != 1 || request->requested_generation == 0 || host->live.id != 0) return PROTO_UI_RUNTIME_INVALID;
  host->next_terminal_id++;
  host->live.id = host->next_terminal_id;
  host->live.generation = request->requested_generation;
  *result = host->live;
  return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus fake_delete(void *context, const ProtoUiIdentity *identity) {
  TestHost *host = context;
  if (host->live.id != identity->id || host->live.generation != identity->generation) return PROTO_UI_RUNTIME_GENERATION_MISMATCH;
  memset(&host->live, 0, sizeof(host->live));
  return PROTO_UI_RUNTIME_OK;
}

static void make_host(TestHost *host) {
  memset(host, 0, sizeof(*host));
  host->terminal = (ProtoUiTerminalGroupV1){1, sizeof(ProtoUiTerminalGroupV1), host, fake_create, ok_identity, fake_delete};
  host->frame = (ProtoUiFrameGroupV1){1, sizeof(ProtoUiFrameGroupV1), host, fake_register, ok_identity, fake_state, fake_geometry};
  host->redisplay = (ProtoUiRedisplayGroupV1){1, sizeof(ProtoUiRedisplayGroupV1), host, fake_capture,
    (ProtoUiCaptureWindowFn)fake_capture_identity,
    (ProtoUiCaptureRowFn)fake_capture_identity, (ProtoUiCaptureRunFn)fake_capture_identity,
    (ProtoUiCaptureCursorFn)fake_capture_identity, (ProtoUiCaptureDamageFn)fake_capture_identity,
    (ProtoUiCaptureFaceFn)fake_capture_identity, (ProtoUiCaptureFontFn)fake_capture_identity,
    (ProtoUiCaptureShapedRunFn)fake_capture_identity,
    (ProtoUiCaptureImageDefineFn)fake_capture_identity,
    (ProtoUiCaptureImageFragmentFn)fake_capture_identity, ok_identity, ok_identity};
  host->input = (ProtoUiInputGroupV1){1, sizeof(ProtoUiInputGroupV1), host, fake_deliver, fake_result, fake_completion};
  host->lifecycle = (ProtoUiLifecycleGroupV1){1, sizeof(ProtoUiLifecycleGroupV1), host, fake_heartbeat, ok_void, fake_diagnostic, ok_void};
}

static ProtoUiPureRuntimeHostV1 host_table(TestHost *host) {
  return (ProtoUiPureRuntimeHostV1){1, sizeof(ProtoUiPureRuntimeHostV1), host,
    &host->terminal, &host->frame, &host->redisplay, &host->input, &host->lifecycle};
}

static ProtoUiTerminalProviderV1 provider(const char *name, void *context) {
  return (ProtoUiTerminalProviderV1){1, PROTO_UI_TPE_FLAG_GRAPHIC | PROTO_UI_TPE_FLAG_INPUT,
    sizeof(ProtoUiTerminalProviderV1), name, name, context,
    fake_create, ok_identity, fake_delete};
}

int proto_ui_tpe_core_test_run(void) {
  TestHost host;
  make_host(&host);
  ProtoUiPureRuntimeHostV1 table = host_table(&host);
  ProtoUiTerminalProviderV1 valid = provider("proto", &host);
  ProtoUiTerminalProviderRegistration *registration = NULL;
  assert(proto_ui_tpe_registry_reset() == PROTO_UI_RUNTIME_OK);
  assert(proto_ui_tpe_provider_register(&valid, &table, &registration) == PROTO_UI_RUNTIME_OK);
  assert(registration != NULL && registration->generation == 1);
  assert(proto_ui_tpe_provider_register(&valid, &table, &registration) == PROTO_UI_RUNTIME_INVALID);

  ProtoUiTerminalCreateRequest request = {1, 1, {0}};
  ProtoUiIdentity terminal = {0};
  assert(proto_ui_tpe_terminal_create(registration, &request, &terminal) == PROTO_UI_RUNTIME_OK);
  assert(terminal.id == 1 && terminal.generation == 1);
  assert(proto_ui_tpe_terminal_activate(registration, &terminal) == PROTO_UI_RUNTIME_OK);
  assert(proto_ui_tpe_terminal_delete(registration, &terminal) == PROTO_UI_RUNTIME_OK);
  assert(proto_ui_tpe_terminal_create(registration, &request, &terminal) == PROTO_UI_RUNTIME_OK);
  assert(terminal.id == 2);
  assert(proto_ui_tpe_terminal_delete(registration, &terminal) == PROTO_UI_RUNTIME_OK);

  ProtoUiTerminalProviderV1 duplicate = provider("other", &host);
  duplicate.identity_symbol = "proto";
  ProtoUiTerminalProviderRegistration *other = NULL;
  assert(proto_ui_tpe_provider_register(&duplicate, &table, &other) == PROTO_UI_RUNTIME_INVALID);
  assert(proto_ui_tpe_provider_unregister(registration) == PROTO_UI_RUNTIME_OK);
  assert(registration->live_terminals == 0);

  ProtoUiTerminalProviderV1 bad = valid;
  bad.create_terminal = NULL;
  assert(proto_ui_tpe_provider_register(&bad, &table, &registration) == PROTO_UI_RUNTIME_INVALID);
  return 0;
}
