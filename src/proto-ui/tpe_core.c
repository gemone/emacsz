#include <config.h>
#include "tpe_core.h"

#include <stddef.h>
#include <string.h>

static ProtoUiTerminalProviderRegistration registrations[PROTO_UI_TPE_MAX_PROVIDERS];
static size_t registration_count;
static uint64_t next_generation;

static ProtoUiPureRuntimeStatus validate_group(
    const void *group, uint32_t abi_version, size_t size, size_t size_offset,
    void *context, const void *const *callbacks, size_t callback_count) {
  if (group == NULL || context == NULL) return PROTO_UI_RUNTIME_INVALID;
  const uint32_t *version = group;
  const size_t *stored_size = (const size_t *)((const unsigned char *)group + size_offset);
  if (*version != abi_version || *stored_size != size) return PROTO_UI_RUNTIME_INVALID;
  for (size_t index = 0; index < callback_count; ++index) {
    if (callbacks[index] == NULL) return PROTO_UI_RUNTIME_INVALID;
  }
  return PROTO_UI_RUNTIME_OK;
}

static ProtoUiPureRuntimeStatus validate_host(
    const ProtoUiPureRuntimeHostV1 *host) {
  if (host == NULL || host->abi_version != PROTO_UI_PURE_RUNTIME_HOST_ABI_VERSION ||
      host->size != PROTO_UI_PURE_RUNTIME_HOST_V1_SIZE || host->context == NULL)
    return PROTO_UI_RUNTIME_INVALID;

#define TPE_GROUP(value, type, ...) do { \
    const void *const callbacks[] = {__VA_ARGS__}; \
    ProtoUiPureRuntimeStatus status = validate_group( \
        value, PROTO_UI_PURE_RUNTIME_HOST_ABI_VERSION, sizeof(type), \
        offsetof(type, size), host->context, callbacks, \
        sizeof(callbacks) / sizeof(callbacks[0])); \
    if (status != PROTO_UI_RUNTIME_OK) return status; \
  } while (0)

  TPE_GROUP(host->terminal, ProtoUiTerminalGroupV1,
            host->terminal->create_terminal, host->terminal->activate_terminal,
            host->terminal->delete_terminal);
  TPE_GROUP(host->frame, ProtoUiFrameGroupV1,
            host->frame->register_frame, host->frame->unregister_frame,
            host->frame->read_frame_state, host->frame->read_geometry);
  TPE_GROUP(host->redisplay, ProtoUiRedisplayGroupV1,
            host->redisplay->begin_capture, host->redisplay->observe_window,
            host->redisplay->observe_row, host->redisplay->observe_run,
            host->redisplay->observe_cursor, host->redisplay->observe_damage,
            host->redisplay->observe_face, host->redisplay->observe_font,
            host->redisplay->observe_shaped_run,
            host->redisplay->observe_image_define,
            host->redisplay->observe_image_fragment,
            host->redisplay->commit_capture, host->redisplay->cancel_capture);
  TPE_GROUP(host->input, ProtoUiInputGroupV1,
            host->input->deliver_event, host->input->deliver_result,
            host->input->deliver_completion_status);
  TPE_GROUP(host->lifecycle, ProtoUiLifecycleGroupV1,
            host->lifecycle->heartbeat, host->lifecycle->flush,
            host->lifecycle->diagnostic,
            host->lifecycle->cancel_all_pending_work);
#undef TPE_GROUP
  return PROTO_UI_RUNTIME_OK;
}

static bool valid_name(const char *value) {
  if (value == NULL) return false;
  size_t length = strlen(value);
  return length > 0 && length < PROTO_UI_TPE_MAX_NAME;
}

static bool same_text(const char *left, const char *right) {
  return left != NULL && right != NULL && strcmp(left, right) == 0;
}

static bool valid_registration(
    const ProtoUiTerminalProviderRegistration *value) {
  if (value == NULL) return false;
  for (size_t index = 0; index < registration_count; ++index) {
    if (&registrations[index] == value) return true;
  }
  return false;
}

ProtoUiPureRuntimeStatus proto_ui_tpe_registry_reset(void) {
  registration_count = 0;
  next_generation = 0;
  memset(registrations, 0, sizeof(registrations));
  return PROTO_UI_RUNTIME_OK;
}

ProtoUiPureRuntimeStatus proto_ui_tpe_provider_register(
    const ProtoUiTerminalProviderV1 *provider,
    const ProtoUiPureRuntimeHostV1 *host,
    ProtoUiTerminalProviderRegistration **output) {
  if (output == NULL) *output = NULL;
  if (provider == NULL || host == NULL || output == NULL ||
      provider->abi_version != PROTO_UI_TPE_ABI_VERSION ||
      provider->size != PROTO_UI_TPE_PROVIDER_V1_SIZE ||
      provider->context == NULL || provider->create_terminal == NULL ||
      provider->activate_terminal == NULL || provider->delete_terminal == NULL)
    return PROTO_UI_RUNTIME_INVALID;
  if ((provider->flags & ~PROTO_UI_TPE_FLAG_SUPPORTED) != 0 ||
      (provider->flags & (PROTO_UI_TPE_FLAG_GRAPHIC | PROTO_UI_TPE_FLAG_INPUT)) !=
          (PROTO_UI_TPE_FLAG_GRAPHIC | PROTO_UI_TPE_FLAG_INPUT) ||
      !valid_name(provider->name) || !valid_name(provider->identity_symbol))
    return PROTO_UI_RUNTIME_INVALID;
  if (validate_host(host) != PROTO_UI_RUNTIME_OK) return PROTO_UI_RUNTIME_INVALID;
  if (registration_count == PROTO_UI_TPE_MAX_PROVIDERS)
    return PROTO_UI_RUNTIME_BUSY;
  for (size_t index = 0; index < registration_count; ++index) {
    const ProtoUiTerminalProviderV1 *existing = &registrations[index].provider;
    if (same_text(existing->name, provider->name) ||
        same_text(existing->identity_symbol, provider->identity_symbol))
      return PROTO_UI_RUNTIME_INVALID;
  }

  ProtoUiTerminalProviderRegistration *entry = &registrations[registration_count++];
  memset(entry, 0, sizeof(*entry));
  entry->provider = *provider;
  entry->host = *host;
  entry->state = PROTO_UI_TPE_REGISTERED;
  entry->generation = ++next_generation;
  *output = entry;
  return PROTO_UI_RUNTIME_OK;
}

ProtoUiPureRuntimeStatus proto_ui_tpe_provider_unregister(
    const ProtoUiTerminalProviderRegistration *registration) {
  if (!valid_registration(registration) || registration->state != PROTO_UI_TPE_REGISTERED ||
      registration->live_terminals != 0)
    return PROTO_UI_RUNTIME_INVALID;
  ProtoUiTerminalProviderRegistration *last = &registrations[--registration_count];
  if (registration != last) {
    ProtoUiTerminalProviderRegistration *mutable_registration =
        (ProtoUiTerminalProviderRegistration *)registration;
    *mutable_registration = *last;
  }
  memset(last, 0, sizeof(*last));
  return PROTO_UI_RUNTIME_OK;
}

static bool terminal_slot(ProtoUiTerminalProviderRegistration *registration,
                          const ProtoUiIdentity *identity, size_t *index) {
  for (size_t candidate = 0; candidate < registration->live_terminals; ++candidate) {
    if (registration->terminals[candidate].id == identity->id &&
        registration->terminals[candidate].generation == identity->generation) {
      *index = candidate;
      return true;
    }
  }
  return false;
}

ProtoUiPureRuntimeStatus proto_ui_tpe_terminal_create(
    ProtoUiTerminalProviderRegistration *registration,
    const ProtoUiTerminalCreateRequest *request,
    ProtoUiIdentity *terminal) {
  if (!valid_registration(registration) || registration->state != PROTO_UI_TPE_REGISTERED ||
      request == NULL || terminal == NULL || registration->live_terminals == 4 ||
      request->requested_generation == 0 || request->kind != 1)
    return PROTO_UI_RUNTIME_INVALID;
  memset(terminal, 0, sizeof(*terminal));
  ProtoUiPureRuntimeStatus status = registration->provider.create_terminal(
      registration->provider.context, request, terminal);
  if (status != PROTO_UI_RUNTIME_OK || terminal->id == 0 || terminal->generation == 0)
    return status == PROTO_UI_RUNTIME_OK ? PROTO_UI_RUNTIME_INVALID : status;
  registration->terminals[registration->live_terminals++] = *terminal;
  return status;
}

ProtoUiPureRuntimeStatus proto_ui_tpe_terminal_activate(
    ProtoUiTerminalProviderRegistration *registration,
    const ProtoUiIdentity *terminal) {
  size_t index;
  if (!valid_registration(registration) || registration->state != PROTO_UI_TPE_REGISTERED ||
      terminal == NULL || !terminal_slot(registration, terminal, &index))
    return PROTO_UI_RUNTIME_INVALID;
  ProtoUiPureRuntimeStatus status = registration->provider.activate_terminal(
      registration->provider.context, terminal);
  if (status != PROTO_UI_RUNTIME_OK) return status;
  return status;
}

ProtoUiPureRuntimeStatus proto_ui_tpe_terminal_delete(
    ProtoUiTerminalProviderRegistration *registration,
    const ProtoUiIdentity *terminal) {
  size_t index;
  if (!valid_registration(registration) || registration->state != PROTO_UI_TPE_REGISTERED ||
      terminal == NULL || !terminal_slot(registration, terminal, &index))
    return PROTO_UI_RUNTIME_INVALID;
  ProtoUiPureRuntimeStatus status = registration->provider.delete_terminal(
      registration->provider.context, terminal);
  if (status != PROTO_UI_RUNTIME_OK) return status;
  memmove(&registration->terminals[index], &registration->terminals[index + 1],
          (registration->live_terminals - index - 1) * sizeof(registration->terminals[0]));
  registration->live_terminals--;
  return status;
}
