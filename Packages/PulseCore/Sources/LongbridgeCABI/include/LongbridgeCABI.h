#ifndef PULSE_LONGBRIDGE_C_ABI_H
#define PULSE_LONGBRIDGE_C_ABI_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/*
 * Minimal mirror of the official Longbridge C ABI (pinned v4.4.1 plus Pulse's
 * OAuth-token patch). macOS resolves the functions with dlsym against the
 * embedded plugin, so only the types matter there; iOS links the SDK's static
 * library directly, so the function prototypes below bind at link time.
 */

typedef struct lb_error_t lb_error_t;
typedef struct lb_decimal_t lb_decimal_t;
typedef struct lb_quote_context_t lb_quote_context_t;
typedef struct lb_config_t lb_config_t;

typedef struct lb_async_result_t {
    const void *ctx;
    const lb_error_t *error;
    void *data;
    uintptr_t length;
    void *userdata;
} lb_async_result_t;

typedef void (*lb_async_callback_t)(const lb_async_result_t *);
typedef void (*lb_free_userdata_func_t)(void *);

typedef struct lb_prepost_quote_t {
    const lb_decimal_t *last_done;
    int64_t timestamp;
    int64_t volume;
    const lb_decimal_t *turnover;
    const lb_decimal_t *high;
    const lb_decimal_t *low;
    const lb_decimal_t *prev_close;
} lb_prepost_quote_t;

typedef struct lb_security_quote_t {
    const char *symbol;
    const lb_decimal_t *last_done;
    const lb_decimal_t *prev_close;
    const lb_decimal_t *open;
    const lb_decimal_t *high;
    const lb_decimal_t *low;
    int64_t timestamp;
    int64_t volume;
    const lb_decimal_t *turnover;
    int32_t trade_status;
    const lb_prepost_quote_t *pre_market_quote;
    const lb_prepost_quote_t *post_market_quote;
    const lb_prepost_quote_t *overnight_quote;
} lb_security_quote_t;

typedef struct lb_security_static_info_t {
    const char *symbol;
    const char *name_cn;
    const char *name_en;
    const char *name_hk;
    const char *exchange;
    const char *currency;
    int32_t lot_size;
    int64_t total_shares;
    int64_t circulating_shares;
    int64_t hk_shares;
    const lb_decimal_t *eps;
    const lb_decimal_t *eps_ttm;
    const lb_decimal_t *bps;
    const lb_decimal_t *dividend_yield;
    uint8_t stock_derivatives;
    int32_t board;
} lb_security_static_info_t;

typedef struct lb_push_quote_t {
    const char *symbol;
    const lb_decimal_t *last_done;
    const lb_decimal_t *open;
    const lb_decimal_t *high;
    const lb_decimal_t *low;
    int64_t timestamp;
    int64_t volume;
    const lb_decimal_t *turnover;
    int32_t trade_status;
    int32_t trade_session;
    int64_t current_volume;
    const lb_decimal_t *current_turnover;
} lb_push_quote_t;

typedef void (*lb_quote_callback_t)(
    const lb_quote_context_t *,
    const lb_push_quote_t *,
    void *
);

typedef struct lb_candlestick_t {
    const lb_decimal_t *close;
    const lb_decimal_t *open;
    const lb_decimal_t *low;
    const lb_decimal_t *high;
    int64_t volume;
    const lb_decimal_t *turnover;
    int64_t timestamp;
    int32_t trade_session;
} lb_candlestick_t;

typedef struct lb_date_t {
    int32_t year;
    uint8_t month;
    uint8_t day;
} lb_date_t;

typedef struct lb_time_t {
    uint8_t hour;
    uint8_t minute;
    uint8_t second;
} lb_time_t;

typedef struct lb_datetime_t {
    lb_date_t date;
    lb_time_t time;
} lb_datetime_t;

typedef struct lb_quote_package_detail_t {
    const char *key;
    const char *name;
    const char *description;
    int64_t start_at;
    int64_t end_at;
} lb_quote_package_detail_t;

/*
 * Prototypes mirror c/csrc/include/longbridge.h of the pinned SDK. Enum-typed
 * parameters (lb_period_t, lb_adjust_type_t, lb_trade_sessions_t) are spelled
 * int32_t: identical ABI on Apple platforms, and it matches the raw values the
 * Swift bridge already passes through the dlsym path.
 */

lb_config_t *lb_config_from_apikey(const char *app_key,
                                   const char *app_secret,
                                   const char *access_token);
/* Added by Pulse's oauth-token-config.patch. */
lb_config_t *lb_config_from_oauth_token(const char *access_token);
void lb_config_enable_overnight(lb_config_t *config);
void lb_config_disable_print_quote_packages(lb_config_t *config);
void lb_config_set_http_url(lb_config_t *config, const char *http_url);
void lb_config_set_quote_ws_url(lb_config_t *config, const char *quote_ws_url);
void lb_config_free(lb_config_t *config);

const lb_quote_context_t *lb_quote_context_new(const lb_config_t *config);
void lb_quote_context_retain(const lb_quote_context_t *ctx);
void lb_quote_context_release(const lb_quote_context_t *ctx);
void lb_quote_context_quote_package_details(const lb_quote_context_t *ctx,
                                            lb_async_callback_t callback,
                                            void *userdata);
void lb_quote_context_set_on_quote(const lb_quote_context_t *ctx,
                                   lb_quote_callback_t callback,
                                   void *userdata,
                                   lb_free_userdata_func_t free_userdata);
void lb_quote_context_static_info(const lb_quote_context_t *ctx,
                                  const char *const *symbols,
                                  uintptr_t num_symbols,
                                  lb_async_callback_t callback,
                                  void *userdata);
void lb_quote_context_quote(const lb_quote_context_t *ctx,
                            const char *const *symbols,
                            uintptr_t num_symbols,
                            lb_async_callback_t callback,
                            void *userdata);
void lb_quote_context_subscribe(const lb_quote_context_t *ctx,
                                const char *const *symbols,
                                uintptr_t num_symbols,
                                uint8_t sub_types,
                                lb_async_callback_t callback,
                                void *userdata);
void lb_quote_context_unsubscribe(const lb_quote_context_t *ctx,
                                  const char *const *symbols,
                                  uintptr_t num_symbols,
                                  uint8_t sub_types,
                                  lb_async_callback_t callback,
                                  void *userdata);
void lb_quote_context_candlesticks(const lb_quote_context_t *ctx,
                                   const char *symbol,
                                   int32_t period,
                                   uintptr_t count,
                                   int32_t adjust_type,
                                   int32_t trade_sessions,
                                   lb_async_callback_t callback,
                                   void *userdata);
void lb_quote_context_history_candlesticks_by_offset(const lb_quote_context_t *ctx,
                                                     const char *symbol,
                                                     int32_t period,
                                                     int32_t adjust_type,
                                                     bool forward,
                                                     const lb_datetime_t *time,
                                                     uintptr_t count,
                                                     int32_t trade_sessions,
                                                     lb_async_callback_t callback,
                                                     void *userdata);

double lb_decimal_to_double(const lb_decimal_t *value);
const char *lb_error_message(const lb_error_t *error);
int64_t lb_error_code(const lb_error_t *error);

#endif
