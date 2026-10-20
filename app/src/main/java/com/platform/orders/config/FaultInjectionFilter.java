package com.platform.orders.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Fails a share of /api/orders requests with HTTP 500 when FAULT_ERROR_RATE > 0.
 * The pipeline bakes a non-zero rate into the image when SIMULATE_BAD_RELEASE is ticked,
 * so the Argo Rollouts canary analysis can be seen rolling a bad release back.
 */
@Component
public class FaultInjectionFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(FaultInjectionFilter.class);

    private final double errorRate;

    public FaultInjectionFilter(@Value("${app.fault.error-rate:0.0}") double errorRate) {
        this.errorRate = errorRate;
        if (errorRate > 0) {
            log.warn("Fault injection is ON: {}% of /api/orders requests will fail", errorRate * 100);
        }
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return errorRate <= 0 || !request.getRequestURI().startsWith("/api/orders");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (ThreadLocalRandom.current().nextDouble() < errorRate) {
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.setContentType("application/json");
            response.getWriter().write("{\"error\":\"injected fault\"}");
            return;
        }
        chain.doFilter(request, response);
    }
}
