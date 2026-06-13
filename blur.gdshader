shader_type canvas_item;

// 模糊强度控制：在右侧 Material 的 Shader Parameters 里你可以随时调整这个数值来改变模糊度
uniform float blur_amount : hint_range(0.0, 5.0) = 2.5;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    COLOR = textureLod(screen_texture, SCREEN_UV, blur_amount);
}