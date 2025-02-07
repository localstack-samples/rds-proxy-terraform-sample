package cloud.localstack.deletedog;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import software.amazon.awssdk.services.rdsdata.RdsDataClient;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.util.Map;

public class DeleteDogHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final String SECRET_ARN = System.getenv("SECRET_ARN");
    private static final String REGION = System.getenv("AWS_REGION");
    private static final String DATABASE_NAME = System.getenv("DATABASE_NAME");
    private static Connection connection;
    private static final String HOST = System.getenv("HOST");

    private final RdsDataClient rdsDataClient;

    public DeleteDogHandler() {
        this.rdsDataClient = RdsDataClient.create();
    }

    {
        connection = DatabaseUtil.getConnectionWithUserPassword(REGION, SECRET_ARN, HOST, DATABASE_NAME);
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {
        try {
            Map<String, Object> pathParameters = (Map<String, Object>) event.get("pathParameters");
            if (pathParameters == null || !pathParameters.containsKey("id")) {
                return Map.of("statusCode", 400, "body", "Missing 'id' in path parameters");
            }
            int dogId = Integer.parseInt((String) pathParameters.get("id"));

            // Delete dog record
            String query = "DELETE FROM Dogs WHERE id = ?";
            PreparedStatement stmt = connection.prepareStatement(query);
            stmt.setInt(1, dogId);

            int rowsAffected = stmt.executeUpdate();

            stmt.close();

            System.out.println("Dog deleted successfully! Rows affected: " + rowsAffected);

            return Map.of("statusCode", 200, "body", "Dog deleted successfully!");
        } catch (Exception e) {
            return Map.of("statusCode", 500, "body", "Error processing request: " + e.getMessage());
        }
    }
}
