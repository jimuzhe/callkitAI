"""
数据库连接管理
"""
import pymysql
from pymysql.cursors import DictCursor
from contextlib import contextmanager
from config import Config


class Database:
    """数据库连接管理类"""
    
    @staticmethod
    @contextmanager
    def get_connection():
        """获取数据库连接的上下文管理器"""
        connection = None
        try:
            connection = pymysql.connect(**Config.DB_CONFIG, cursorclass=DictCursor)
            yield connection
        except pymysql.Error as e:
            if connection:
                connection.rollback()
            raise e
        finally:
            if connection:
                connection.close()
    
    @staticmethod
    @contextmanager
    def get_cursor():
        """获取游标的上下文管理器"""
        with Database.get_connection() as conn:
            cursor = conn.cursor()
            try:
                yield cursor
                conn.commit()
            except Exception as e:
                conn.rollback()
                raise e
            finally:
                cursor.close()
