package com.telecom.pubsub.alert.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class SwaggerConfig {
    @Bean
    public OpenAPI openAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("Usage Alert Subscriber API")
                        .description("사용량 초과 알림 처리 API")
                        .version("1.0.0"));
    }
}
