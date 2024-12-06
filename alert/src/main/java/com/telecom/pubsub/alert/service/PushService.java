package com.telecom.pubsub.alert.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class PushService {
    public void sendPush(String userId, String content) {
        // Push 알림 발송 로직 구현 (실습을 위해 로그만 출력)
        log.info("Push notification sent to user {}: {}", userId, content);
    }
}
