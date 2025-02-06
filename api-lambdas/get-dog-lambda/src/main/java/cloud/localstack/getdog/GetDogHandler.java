package cloud.localstack.getdog;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.services.rdsdata.RdsDataClient;
import software.amazon.awssdk.services.rdsdata.model.ExecuteStatementRequest;
import software.amazon.awssdk.services.rdsdata.model.ExecuteStatementResponse;
import software.amazon.awssdk.services.rdsdata.model.Field;
import software.amazon.awssdk.services.rdsdata.model.SqlParameter;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class GetDogHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final ObjectMapper objectMapper = new ObjectMapper();
    private static final String SECRET_ARN = System.getenv("SECRET_ARN");
    private static final String DATABASE_NAME = System.getenv("DATABASE_NAME");
    private static final String DB_CLUSTER_ARN = System.getenv("DB_CLUSTER_ARN");
    private final RdsDataClient rdsDataClient;

    public GetDogHandler() {
        this.rdsDataClient = RdsDataClient.create();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {
        try {
            // Extract path parameter from API Gateway
            Map<String, Object> pathParameters = (Map<String, Object>) event.get("pathParameters");
            if (pathParameters == null || !pathParameters.containsKey("id")) {
                return Map.of("statusCode", 400, "body", "Missing 'id' in path parameters");
            }
            String dogId = pathParameters.get("id").toString();

            String sql = "SELECT id, name, age, category FROM dogs WHERE id = :id";

            ExecuteStatementRequest request = ExecuteStatementRequest.builder()
                    .database(DATABASE_NAME)
                    .resourceArn(DB_CLUSTER_ARN)
                    .secretArn(SECRET_ARN)
                    .sql(sql)
                    .parameters(
                            SqlParameter.builder().name("id").value(Field.builder().stringValue(dogId).build()).build()
                    )
                    .build();

            ExecuteStatementResponse response = rdsDataClient.executeStatement(request);

            if (response.records().isEmpty()) {
                return Map.of("statusCode", 404, "body", "Dog not found");
            }

            Map<String, Object> dog = new HashMap<>();
            List<Field> record = response.records().get(0);


            dog.put("id", record.get(0).longValue());
            dog.put("name", record.get(1).stringValue());
            dog.put("age", record.get(2).longValue());
            dog.put("category", record.get(3).stringValue());

            return Map.of("statusCode", 200, "body", objectMapper.writeValueAsString(dog));
        } catch (Exception e) {
            return Map.of("statusCode", 500, "body", "Error processing request: " + e.getMessage());
        }
    }
}
