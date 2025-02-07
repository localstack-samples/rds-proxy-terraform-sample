package cloud.localstack.initdb;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import org.json.JSONObject;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Map;

public class InitDBHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final String DB_SECRET_ARN = System.getenv("DB_SECRET_ARN");
    private static final Region REGION = Region.of(System.getenv("AWS_REGION"));
    private static final String ENDPOINT = System.getenv("RDS_PROXY_ENDPOINT");
    private static final String DB_NAME = System.getenv("DB_NAME");


    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        try (Connection conn = getDbConnection();
             Statement stmt = conn.createStatement()) {

            // Create the dogs table
            String createTableQuery = "CREATE TABLE IF NOT EXISTS dogs (" +
                    "id SERIAL PRIMARY KEY, " +
                    "name VARCHAR(100), " +
                    "age INT, " +
                    "category VARCHAR(50))";
            stmt.executeUpdate(createTableQuery);

            // Create user token_user
            stmt.executeUpdate("CREATE USER token_user");

            // Grant roles to token_user
            stmt.executeUpdate("GRANT rds_iam TO token_user");
            stmt.executeUpdate("ALTER USER token_user WITH LOGIN");
            stmt.executeUpdate("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO token_user");
            stmt.executeUpdate("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO token_user");
            stmt.executeUpdate("GRANT USAGE, SELECT, UPDATE ON SEQUENCE dogs_id_seq TO token_user");

            // Grant roles to lambda_user
            stmt.executeUpdate("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lambda_user");
            stmt.executeUpdate("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO lambda_user");
            stmt.executeUpdate("GRANT USAGE, SELECT, UPDATE ON SEQUENCE dogs_id_seq TO lambda_user");

            return Map.of(
                    "statusCode", 200,
                    "body", "Table created and roles granted successfully!"
            );

        } catch (SQLException e) {
            e.printStackTrace();
            return Map.of(
                    "statusCode", 500,
                    "body", "Error: " + e.getMessage()
            );
        }
    }


    private static Map<String, String> getDatabaseCredentials() {


        try (SecretsManagerClient secretsClient = SecretsManagerClient.builder()
                .region(REGION)
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build()) {

            GetSecretValueRequest secretRequest = GetSecretValueRequest.builder()
                    .secretId(DB_SECRET_ARN)
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

    private static Connection getDbConnection() {
        Map<String, String> creds = getDatabaseCredentials();
        String jdbcUrl = String.format("jdbc:postgresql://%s/%s",
                ENDPOINT, DB_NAME);

        try {
            return DriverManager.getConnection(jdbcUrl, creds.get("username"), creds.get("password"));
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Database connection failed", e);
        }
    }

}
