FROM node:24-alpine AS build
WORKDIR /app
COPY John-Deere-MultiAgents-Website/package*.json ./
RUN npm ci
COPY John-Deere-MultiAgents-Website/ ./
ARG VITE_GAME_URL=/unity/Build
ENV VITE_API_URL=/backend VITE_GAME_URL=${VITE_GAME_URL}
RUN npm run build -- --base=/

FROM nginx:stable-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
