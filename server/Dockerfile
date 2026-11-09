# Licence server image.  docker build -t aurora-license . && docker run -p 8080:8080 --env-file .env aurora-license
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
ENV DATA_DIR=/data
EXPOSE 8080
CMD ["/app/server"]
