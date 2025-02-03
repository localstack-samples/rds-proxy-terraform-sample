package cloud.localstack.putdog;

import org.json.JSONObject;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.rds.RdsUtilities;
import software.amazon.awssdk.services.rds.model.GenerateAuthenticationTokenRequest;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Map;

public class DatabaseUtil {

    /**
     * Retrieve database credentials from AWS Secrets Manager.
     */
    private static Map<String, String> getDatabaseCredentials(String region, String dbSecretArn) {
        try (SecretsManagerClient secretsClient = SecretsManagerClient.builder()
                .region(Region.of(region))
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build()) {

            GetSecretValueRequest secretRequest = GetSecretValueRequest.builder()
                    .secretId(dbSecretArn)
                    .build();

            GetSecretValueResponse secretResponse = secretsClient.getSecretValue(secretRequest);
            String secretJson = secretResponse.secretString();
            JSONObject secretObj = new JSONObject(secretJson);

            return Map.of(
                    "username", secretObj.getString("username"),
                    "password", secretObj.getString("password")
            );

        } catch (Exception e) {
            throw new RuntimeException("Error retrieving secrets from Secrets Manager", e);
        }
    }

    /**
     * Get database connection using username and password retrieved from AWS Secrets Manager.
     */
    public static Connection getConnectionWithUserPassword(String region, String dbSecretArn, String host, String databaseName) {
        Map<String, String> creds = getDatabaseCredentials(region, dbSecretArn);
        String jdbcUrl = String.format("jdbc:postgresql://%s/%s?ssl=true&sslmode=require",
                host, databaseName);

        try {
            return DriverManager.getConnection(jdbcUrl, creds.get("username"), creds.get("password"));
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Database connection failed using username/password", e);
        }
    }

    /**
     * Creates a database connection using IAM authentication token.
     */
    public static Connection getConnectionWithIamAuth(String username, String host, Integer port, String region, String databaseName) {

        String authToken = generateAuthToken(host, port, region, username);
        String jdbcUrl = String.format("jdbc:postgresql://%s/%s",
                host, databaseName);

        try {
            return DriverManager.getConnection(jdbcUrl, username, authToken);
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Database connection failed using IAM authentication", e);
        }
    }

    private static String generateAuthToken(String hostName, Integer port, String region,String username) {

        RdsUtilities utilities = RdsUtilities.builder()
                .credentialsProvider(DefaultCredentialsProvider.create())
                .region(Region.of(region))
                .build();

        GenerateAuthenticationTokenRequest authTokenRequest = GenerateAuthenticationTokenRequest.builder()
                .username(username)
                .hostname(hostName)
                .port(port)
                .build();

        return utilities.generateAuthenticationToken(authTokenRequest);
    }
}
