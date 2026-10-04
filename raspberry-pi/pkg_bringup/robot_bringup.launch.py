from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, ExecuteProcess
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    serial_port    = LaunchConfiguration('serial_port')
    baudrate       = LaunchConfiguration('baudrate')
    gps_port       = LaunchConfiguration('gps_port')
    gps_baudrate   = LaunchConfiguration('gps_baudrate')
    pressed_value  = LaunchConfiguration('pressed_value')
    rosbridge_port = LaunchConfiguration('rosbridge_port')
    web_video_port = LaunchConfiguration('web_video_port')

    return LaunchDescription([
        DeclareLaunchArgument(
            'serial_port',
            default_value='/dev/ttyACM0',
            description='Puerto serial del ESP32',
        ),
        DeclareLaunchArgument(
            'baudrate',
            default_value='115200',
            description='Baudrate del ESP32',
        ),
        DeclareLaunchArgument(
            'gps_port',
            default_value='/dev/ttyAMA3',
            description='Puerto UART del GPS conectado al Raspberry',
        ),
        DeclareLaunchArgument(
            'gps_baudrate',
            default_value='9600',
            description='Baudrate del GPS',
        ),
        DeclareLaunchArgument(
            'pressed_value',
            default_value='1',
            description='Valor que representa bumper presionado: 1 o 0',
        ),
        DeclareLaunchArgument(
            'rosbridge_port',
            default_value='9090',
            description='Puerto WebSocket para rosbridge',
        ),

        DeclareLaunchArgument(
            'web_video_port',
            default_value='8080',
            description='Puerto para el streaming de video web',
        ),
        # ── ESP32 bridge ─────────────────────────────────────────────────
        # Publica: /motors/ticks, /imu/angles, /ultrasonic/*, /bumper/*
        # Recibe:  /esp32/cmd_motores
        Node(
            package='pkg_esp32_bridge',
            executable='esp32_bridge_node',
            name='esp32_bridge_node',
            output='screen',
            parameters=[
                {'port': serial_port},
                {'baudrate': baudrate},
                {'status_period': 0.2},
                {'auto_request_status': True},
            ],
        ),

        Node(
            package='pkg_actuadores',
            executable='buzzer_node',
            name='buzzer_node',
            output='screen',
            parameters=[
                {'voltaje_bateria_baja': 11.0},
            ],
        ),

        Node(
            package='pkg_actuadores',
            executable='blade_node',
            name='blade_node',
            output='screen',
        ),
    
        # ── GPS directo al Raspberry por UART ────────────────────────────
        # Publica: /gps/fix, /gps/speed, /gps/satellites
        Node(
            package='pkg_sensores',
            executable='gps_uart_node',
            name='gps_uart_node',
            output='screen',
            parameters=[
                {'port': gps_port},
                {'baudrate': gps_baudrate},
            ],
        ),

        Node(
            package='pkg_sensores',
            executable='final_carrera_node',
            name='limit_switch_node',
            output='screen',
        ),


        # ── Visión ───────────────────────────────────────────────────────

        # rpicam-vid debe estar escuchando antes de iniciar el bringup.
        ExecuteProcess(
        cmd=[
            'rpicam-vid',
            '-t', '0',
            '--width', '320',
            '--height', '240',
            '--framerate', '15',
            '--codec', 'mjpeg',
            '--inline',
            '--listen',
            '-o', 'tcp://127.0.0.1:8888',
        ],
        output='screen',
    ),

        Node(
            package='pkg_vision',
            executable='camera_bridge_node',
            name='camera_bridge_node',
            output='screen',
            parameters=[
                {'stream_url': 'tcp://127.0.0.1:8888'},
                {'image_topic': '/camera/image_raw'},
                {'publish_fps': 15.0},
            ],
        ),

        Node(
            package='pkg_vision',
            executable='grass_detector_node',
            name='grass_detector_node',
            output='screen',
            parameters=[
                {'image_topic': '/camera/image_raw'},
            ],
        ),

        Node(
            package='pkg_vision',
            executable='object_detection_node',
            name='object_detection_node',
            output='screen',
            parameters=[
                {'image_topic': '/camera/image_raw'},
            ],
        ),


        Node(
            package='web_video_server',
            executable='web_video_server',
            name='web_video_server',
            output='screen',
            parameters=[
                {'port': web_video_port},
                {'address': '0.0.0.0'},
            ],
        ),

        # ── Navegación ───────────────────────────────────────────────────
        # fence_node: recibe /fence/polygon de la app, publica frame local
        Node(
            package='pkg_navegacion',
            executable='fence_node',
            name='fence_node',
            output='screen',
        ),

        # Node(
        #     package='pkg_navegacion',
        #     executable='perimetral_node',
        #     name='perimetral_node',
        #     output='screen',
        # ),

        # Node(
        #     package='pkg_navegacion',
        #     executable='random_node',
        #     name='random_node',
        #     output='screen',
        # ),

        # Node(
        #     package='pkg_navegacion',
        #     executable='parallel_lines_node',
        #     name='parallel_lines_node',
        #     output='screen',
        # ),

        Node(
            package='pkg_navegacion',
            executable='robot_gps_track_node',
            name='robot_gps_track_node',
            output='screen',
            parameters=[
                {'periodo_muestreo_s': 5.0},
                {'distancia_min_m': 0.5},
                {'puntos_max': 1000},
            ],
        ),

        # ── App web ──────────────────────────────────────────────────────
        Node(
            package='rosbridge_server',
            executable='rosbridge_websocket',
            name='rosbridge_websocket',
            output='screen',
            parameters=[
                {'port': rosbridge_port},
            ],
        ),

    ])
