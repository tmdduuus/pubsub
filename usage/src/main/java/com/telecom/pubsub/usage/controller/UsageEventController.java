package com.telecom.pubsub.usage.controller;

import com.telecom.pubsub.usage.service.UsageEventService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/usage")
@RequiredArgsConstructor
@Tag(name = "Usage Event API", description = "사용량 이벤트 발행 API")
public class UsageEventController {
    private final UsageEventService eventService;

    @Operation(summary = "사용량 초과 이벤트 발행", description = "사용자의 데이터 사용량이 임계치를 초과하면 이벤트를 발행합니다.")
    @PostMapping("/events")
    public ResponseEntity<String> publishEvent(
            @RequestParam String userId,
            @RequestParam double usage,
            @RequestParam double threshold) {
        eventService.publishUsageEvent(userId, usage, threshold);
        return ResponseEntity.ok("이벤트가 발행되었습니다.");
    }
}
