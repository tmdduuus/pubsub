package com.telecom.pubsub.common.event;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ValidationEvent {
    private String id;
    private String topic;
    private String subject;
    private ValidationEventData data;
    private String eventType;
    private String eventTime;
    private String metadataVersion;
    private String dataVersion;
}
