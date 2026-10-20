# Runtime image only. The JAR is built and tested by Maven in the Jenkins
# "Build & Test" stage, so run `mvn -B package` before `docker build` locally.
FROM eclipse-temurin:21-jre-noble

ARG APP_VERSION=local
# Non-zero only when the pipeline's SIMULATE_BAD_RELEASE parameter is ticked.
ARG FAULT_ERROR_RATE=0.0

ENV APP_VERSION=${APP_VERSION} \
    FAULT_ERROR_RATE=${FAULT_ERROR_RATE} \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"

RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --chown=10001:10001 target/order-service.jar app.jar

# Numeric UID so Kubernetes can verify runAsNonRoot.
USER 10001:10001
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
