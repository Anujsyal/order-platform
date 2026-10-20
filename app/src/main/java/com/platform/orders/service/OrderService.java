package com.platform.orders.service;

import com.platform.orders.model.Order;
import com.platform.orders.model.OrderStatus;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * In-memory store - the point of this project is the delivery platform, not persistence.
 */
@Service
public class OrderService {

    private final Map<Long, Order> orders = new ConcurrentHashMap<>();
    private final AtomicLong ids = new AtomicLong();
    private final Counter ordersCreated;

    public OrderService(MeterRegistry registry) {
        this.ordersCreated = Counter.builder("orders.placed")
                .description("Number of orders created")
                .register(registry);
    }

    public Order create(String item, int quantity) {
        long id = ids.incrementAndGet();
        Order order = new Order(id, item, quantity, OrderStatus.CREATED, Instant.now());
        orders.put(id, order);
        ordersCreated.increment();
        return order;
    }

    public List<Order> findAll() {
        return orders.values().stream()
                .sorted(Comparator.comparingLong(Order::id))
                .toList();
    }

    public Optional<Order> findById(long id) {
        return Optional.ofNullable(orders.get(id));
    }
}
