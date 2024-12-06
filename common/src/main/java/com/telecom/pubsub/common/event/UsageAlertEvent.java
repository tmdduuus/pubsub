package com.telecom.pubsub.common.event;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UsageAlertEvent {
    private String eventId;
    private String type;
    private String userId;
    private double usage;
    private double threshold;
    private String timestamp;
}
