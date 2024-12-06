package com.telecom.pubsub.common.model;

import lombok.Builder;
import lombok.Data;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.LocalDateTime;

@Data
@Builder
@Document(collection = "notification_history")
public class NotificationHistory {
    @Id
    private String id;
    private String userId;
    private String notificationType;
    private String content;
    private LocalDateTime sentAt;
    private String status;
}
