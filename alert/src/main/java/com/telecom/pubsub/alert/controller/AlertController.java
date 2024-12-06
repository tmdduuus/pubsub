package com.telecom.pubsub.alert.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.telecom.pubsub.alert.service.NotificationService;
import com.telecom.pubsub.common.event.UsageAlertEvent;
import com.telecom.pubsub.common.event.ValidationEvent;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api/events")
public class AlertController {

    @Autowired
    private NotificationService notificationService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @PostMapping("/usage")
    public ResponseEntity<?> handleEvent(
            @RequestHeader(value = "aeg-event-type", required = false) String eventType,
            @RequestBody String requestBody) {
        try {
            // validation 요청 처리
            log.debug("#### Event Type: {}", eventType);

            if ("SubscriptionValidation".equals(eventType)) {
                ValidationEvent[] events = objectMapper.readValue(requestBody, ValidationEvent[].class);
                String validationCode = events[0].getData().getValidationCode();

                log.info("Validation code: {}", validationCode);
                Map<String, String> response = new HashMap<>();
                response.put("validationResponse", validationCode);
                return ResponseEntity.ok(response);
            }
            // 실제 이벤트 처리
            log.info("Processing event: {}", requestBody);

            // JSON 문자열을 UsageAlertEvent 객체로 변환
            JsonNode eventNode = objectMapper.readTree(requestBody).get(0);
            UsageAlertEvent event = objectMapper.treeToValue(eventNode.get("data"), UsageAlertEvent.class);

            // 이벤트 처리
            notificationService.processEvent(event);

            return ResponseEntity.ok().build();

        } catch (Exception e) {
            log.error("Error processing event", e);
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping("/health")
    public ResponseEntity<String> healthCheck() {
        return ResponseEntity.ok("OK");
    }
}
