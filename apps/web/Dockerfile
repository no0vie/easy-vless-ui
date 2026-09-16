# Build with the repository root as the Docker context.
FROM node:22-alpine AS build
WORKDIR /app
COPY . .
RUN npm ci --include=dev && npm run build --workspace=@easy-vless/web

FROM nginx:stable-alpine
COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/apps/web/dist /usr/share/nginx/html
EXPOSE 80
