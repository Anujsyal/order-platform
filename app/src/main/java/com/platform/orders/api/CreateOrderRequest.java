package com.platform.orders.api;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

public record CreateOrderRequest(
        @NotBlank String item,
        @Min(1) @Max(1000) int quantity) {
}
