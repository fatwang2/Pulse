#ifndef PULSE_LONGBRIDGE_C_ABI_H
#define PULSE_LONGBRIDGE_C_ABI_H

#include <stdint.h>
#include <stddef.h>

/*
 * Minimal type-only mirror of the official Longbridge C ABI used by Pulse's
 * Debug dynamic loader. Functions are resolved with dlsym, so this target has
 * no link-time dependency on the SDK.
 */

typedef struct lb_error_t lb_error_t;
typedef struct lb_decimal_t lb_decimal_t;
typedef struct lb_quote_context_t lb_quote_context_t;

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

#endif
