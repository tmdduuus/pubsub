package com.telecom.pubsub.alert.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class SmsService {
    public void sendSms(String userId, String content) {
        // SMS 발송 로직 구현 (실습을 위해 로그만 출력)
        log.info("SMS sent to user {}: {}", userId, content);
    }
}
