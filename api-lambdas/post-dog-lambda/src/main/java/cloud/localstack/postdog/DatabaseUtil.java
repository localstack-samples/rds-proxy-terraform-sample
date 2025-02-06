package cloud.localstack.postdog;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

public class DatabaseUtil {


    /**
     * Get database connection using username and password using the RDS Proxy
     */
    public static Connection getConnectionWithUserPassword(String host, String databaseName, String username, String password) {
        String jdbcUrl = String.format("jdbc:postgresql://%s/%s",
                host, databaseName);

        try {
            return DriverManager.getConnection(jdbcUrl, username, password);
        } catch (SQLException e) {
            e.printStackTrace();
            throw new RuntimeException("Database connection failed using username/password", e);
        }
    }

}
