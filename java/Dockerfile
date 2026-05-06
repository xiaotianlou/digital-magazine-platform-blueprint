# Spring Boot 3.4 + Java 17 minimal PDF.js demo
# build: docker build -t magazine-java-demo .
# run:   docker run -p 8092:8092 magazine-java-demo
FROM eclipse-temurin:17-jdk-alpine AS builder

WORKDIR /build

# 装 maven
RUN apk add --no-cache maven

# 拷 pom.xml 先装依赖(layer 缓存)
COPY pom.xml .
RUN mvn dependency:go-offline -B 2>&1 | tail -5

# 拷源码 + 资源 + 打包
COPY src ./src
RUN mvn clean package -DskipTests -B 2>&1 | tail -10

# 运行 stage(轻量 JRE only)
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=builder /build/target/pdfdemo-*.jar app.jar
EXPOSE 8092
CMD ["java", "-jar", "app.jar"]
