package com.platform.orders.api;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Reports the running build. The Jenkins pipeline polls this endpoint to confirm
 * that a promotion actually reached an environment.
 */
@RestController
public class VersionController {

    private final String version;
    private final String environment;

    public VersionController(@Value("${app.version}") String version,
                             @Value("${app.environment}") String environment) {
        this.version = version;
        this.environment = environment;
    }

    @GetMapping("/api/version")
    public Map<String, String> version() {
        return Map.of(
                "service", "order-service",
                "version", version,
                "environment", environment);
    }
}
