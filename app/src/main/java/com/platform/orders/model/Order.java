package com.platform.orders.model;

import java.time.Instant;

public record Order(long id, String item, int quantity, OrderStatus status, Instant createdAt) {
}
