package com.telecom.pubsub.usage.config;

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
                        .title("Usage Event Publisher API")
                        .description("사용량 초과 이벤트 발행 API")
                        .version("1.0.0"));
    }
}
