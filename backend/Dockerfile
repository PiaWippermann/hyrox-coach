# Build-Kontext ist das Repo-Root (damit contracts/ mitkommt):
#   docker build -f backend/Dockerfile -t hyrox-coach-api .
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY backend/HyroxCoach.Api/HyroxCoach.Api.csproj backend/HyroxCoach.Api/
COPY contracts/ contracts/
RUN dotnet restore backend/HyroxCoach.Api/HyroxCoach.Api.csproj
COPY backend/ backend/
RUN dotnet publish backend/HyroxCoach.Api/HyroxCoach.Api.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "HyroxCoach.Api.dll"]
