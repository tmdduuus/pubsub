package com.telecom.pubsub.common.event;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ValidationEventData {
    private String validationCode;
    private String validationUrl;
}

