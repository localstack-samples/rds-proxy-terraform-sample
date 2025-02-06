package cloud.localstack.putdog;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Map;


public class UpdateDogHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final ObjectMapper objectMapper = new ObjectMapper();
    private static final String REGION = System.getenv("AWS_REGION");
    private static final int PORT = 4510;
    private static final String DB_USER = System.getenv("DB_USER");
    private static final String DATABASE_NAME = System.getenv("DATABASE_NAME");
    private static Connection connection;
    private static final String HOST = System.getenv("HOST");

    {
        connection = DatabaseUtil.getConnectionWithIamAuth(DB_USER, HOST, PORT, REGION, DATABASE_NAME);
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {


        try {
            // Parse request body
            String requestBody = (String) event.get("body");
            Map<String, Object> body = objectMapper.readValue(requestBody, Map.class);
            int id = Integer.parseInt((String) body.get("id"));
            String name = (String) body.get("name");
            Double age = body.get("age") != null ? Double.parseDouble(body.get("age").toString()) : null;
            String category = (String) body.get("category");

            if (name == null || age == null || category == null) {
                return Map.of("statusCode", 400, "body", "All fields (name, age, category) are required.");
            }

            String checkQuery = "SELECT COUNT(*) FROM dogs WHERE id = ?";
            PreparedStatement checkStmt = connection.prepareStatement(checkQuery);
            checkStmt.setInt(1, id);
            ResultSet resultSet = checkStmt.executeQuery();

            boolean recordExists = false;
            if (resultSet.next()) {
                recordExists = resultSet.getInt(1) > 0;
            }

            resultSet.close();
            checkStmt.close();

            if (recordExists) {
                String updateQuery = "UPDATE dogs SET name = ?, age = ?, category = ? WHERE id = ?";
                PreparedStatement updateStmt = connection.prepareStatement(updateQuery);
                updateStmt.setString(1, name);
                updateStmt.setDouble(2, age);
                updateStmt.setString(3, category);
                updateStmt.setInt(4, id);

                int rowsAffected = updateStmt.executeUpdate();
                System.out.println("Update successful! Rows affected: " + rowsAffected);

                updateStmt.close();
                return Map.of("statusCode", 200, "body", "Dog updated successfully!");

            } else {
                System.out.println("No update performed. Record with ID " + id + " does not exist.");
                return Map.of("statusCode", 404, "body", "Dog not found.");

            }


        } catch (Exception e) {
            return Map.of("statusCode", 500, "body", "Error processing request: " + e.getMessage());
        }
    }

}
