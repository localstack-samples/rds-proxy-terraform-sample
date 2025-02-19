package cloud.localstack.putdog;

import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.rds.RdsUtilities;
import software.amazon.awssdk.services.rds.model.GenerateAuthenticationTokenRequest;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Properties;

public class DatabaseUtil {


    /**
     * Creates a database connection using IAM authentication token.
     */
    public static Connection getConnectionWithIamAuth(String username, String host, Integer port, String region, String databaseName) {

        String authToken = generateAuthToken(host, port, region, username);
        System.out.println("Auth token: " + authToken);
        String jdbcUrl = String.format("jdbc:postgresql://%s/%s?sslmode=require",
                host, databaseName);

        try {
            Properties properties = new Properties();
            properties.setProperty("user", username);
            properties.setProperty("password", authToken);

            return DriverManager.getConnection(jdbcUrl, properties);
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Database connection failed using IAM authentication", e);
        }
    }

    private static String generateAuthToken(String hostName, Integer port, String region, String username) {

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
