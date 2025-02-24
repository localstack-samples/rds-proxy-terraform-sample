package cloud.localstack.postdog;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.util.Map;


public class AddDogHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final ObjectMapper objectMapper = new ObjectMapper();
    private static final String DB_USER = System.getenv("DB_USER");
    private static final String USER_PASSWORD = System.getenv("USER_PASSWORD");

    private static final String DATABASE_NAME = System.getenv("DATABASE_NAME");
    private static Connection connection;
    private static final String HOST = System.getenv("HOST");

    {
        connection = DatabaseUtil.getConnectionWithUserPassword(HOST, DATABASE_NAME, DB_USER, USER_PASSWORD);
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {


        try {
            // Parse request body
            String requestBody = (String) event.get("body");
            Map<String, Object> body = objectMapper.readValue(requestBody, Map.class);

            String name = (String) body.get("name");
            Double age = body.get("age") != null ? Double.parseDouble(body.get("age").toString()) : null;
            String category = (String) body.get("category");

            if (name == null || age == null || category == null) {
                return Map.of("statusCode", 400, "body", "All fields (name, age, category) are required.");
            } else {
                // Insert new dog record
                String query = "INSERT INTO dogs (name, age, category) VALUES (?, ?, ?)";
                PreparedStatement stmt = connection.prepareStatement(query);
                stmt.setString(1, name);
                stmt.setDouble(2, age);
                stmt.setString(3, category);

                int rowsAffected = stmt.executeUpdate();

                stmt.close();

                System.out.println("Dog added successfully! Rows affected: " + rowsAffected);
                return Map.of("statusCode", 200, "body", "Dog added successfully!");

            }

        } catch (Exception e) {
            return Map.of("statusCode", 500, "body", "Error processing request: " + e.getMessage());
        }
    }

}
