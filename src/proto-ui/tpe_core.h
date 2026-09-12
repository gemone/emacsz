/* Generic Terminal Provider Extension v1 registry ABI. */
#ifndef PROTO_UI_TPE_CORE_V1_H
#define PROTO_UI_TPE_CORE_V1_H

#include <stdbool.h>
#ifdef HAVE_CONFIG_H
#include <config.h>
#endif
#include <stddef.h>
#include <stdint.h>
#include "pure_runtime_host_v1.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PROTO_UI_TPE_ABI_VERSION 1u
#define PROTO_UI_TPE_PROVIDER_V1_SIZE sizeof(ProtoUiTerminalProviderV1)
#define PROTO_UI_TPE_FLAG_GRAPHIC 1u
#define PROTO_UI_TPE_FLAG_INPUT 2u
#define PROTO_UI_TPE_FLAG_SELECTION 4u
#define PROTO_UI_TPE_FLAG_TOOLTIP 8u
#define PROTO_UI_TPE_FLAG_MENU 16u
#define PROTO_UI_TPE_FLAG_IMAGE 32u
#define PROTO_UI_TPE_FLAG_SUPPORTED 63u
#define PROTO_UI_TPE_MAX_PROVIDERS 4u
#define PROTO_UI_TPE_MAX_NAME 32u

typedef enum ProtoUiTerminalProviderState {
  PROTO_UI_TPE_REGISTERED = 1,
  PROTO_UI_TPE_QUARANTINED = 2
} ProtoUiTerminalProviderState;

typedef struct ProtoUiTerminalProviderV1 {
  uint32_t abi_version;
  uint32_t flags;
  size_t size;
  const char *name;
  const char *identity_symbol;
  void *context;
  ProtoUiTerminalCreateFn create_terminal;
  ProtoUiIdentityOperationFn activate_terminal;
  ProtoUiIdentityOperationFn delete_terminal;
} ProtoUiTerminalProviderV1;

typedef struct ProtoUiTerminalProviderRegistration {
  ProtoUiTerminalProviderV1 provider;
  ProtoUiPureRuntimeHostV1 host;
  ProtoUiTerminalProviderState state;
  uint64_t generation;
  size_t live_terminals;
  ProtoUiIdentity terminals[4];
} ProtoUiTerminalProviderRegistration;

ProtoUiPureRuntimeStatus proto_ui_tpe_registry_reset(void);
ProtoUiPureRuntimeStatus proto_ui_tpe_provider_register(
    const ProtoUiTerminalProviderV1 *provider,
    const ProtoUiPureRuntimeHostV1 *host,
    ProtoUiTerminalProviderRegistration **registration);
ProtoUiPureRuntimeStatus proto_ui_tpe_provider_unregister(
    const ProtoUiTerminalProviderRegistration *registration);
ProtoUiPureRuntimeStatus proto_ui_tpe_terminal_create(
    ProtoUiTerminalProviderRegistration *registration,
    const ProtoUiTerminalCreateRequest *request,
    ProtoUiIdentity *terminal);
ProtoUiPureRuntimeStatus proto_ui_tpe_terminal_activate(
    ProtoUiTerminalProviderRegistration *registration,
    const ProtoUiIdentity *terminal);
ProtoUiPureRuntimeStatus proto_ui_tpe_terminal_delete(
    ProtoUiTerminalProviderRegistration *registration,
    const ProtoUiIdentity *terminal);

#ifdef __cplusplus
}
#endif
#endif
