const path = require('path');
const webpack = require('webpack');
const BundleAnalyzerPlugin = require("webpack-bundle-analyzer").BundleAnalyzerPlugin;
const { VueLoaderPlugin } = require('vue-loader');
const execSync = require('child_process').execSync;

let commitShaId;

try {
  commitShaId = '#' + execSync('git rev-parse HEAD').toString().substr(0, 10);
}
catch (e) {
}

const mode = process.env.NODE_ENV || 'development';

module.exports = {
  mode,
  entry: {
    upload: './src/upload.js',
    download: './src/download.js',
    admin: './src/admin.js',
  },
  output: {
    path: path.resolve(__dirname, '../public/app'),
    publicPath: '/app/',
    filename: '[name].js'
  },
  optimization: {
    splitChunks: {
      chunks: 'all',
      minChunks: 2,
      name: 'common'
    }
  },
  devtool: 'source-map',
  // devtool: 'none',
  module: {
    rules: [
      {
        test: /\.vue$/,
        loader: 'vue-loader',
        options: {
          // Keep Vue 2's whitespace handling so spacing between icons and text is unchanged
          compilerOptions: { whitespace: 'preserve' }
        }
      },
      {
        test: /\.js$/,
        exclude: /node_modules\/(?!drag-drop\/).*/,
        use: {
          loader: 'babel-loader',
          options: {
            presets: [['@babel/preset-env', {
              modules: false,
              useBuiltIns: false,
              targets: "last 2 versions, not ie 11, not dead",
            }]],
          }
        }
      },
      {
        test: /\.pug$/,
        oneOf: [
          // this applies to `<template lang="pug">` in Vue components
          {
            resourceQuery: /^\?vue/,
            use: ['pug-plain-loader']
          },
          // this applies to pug imports inside JavaScript
          {
            use: ['raw-loader', 'pug-plain-loader']
          }
        ]
      },
      {
        test: /\.css$/,
        use: [
          'style-loader',
          'css-loader',
        ]
      },
      {
        test: /\.(png|jpg|gif|svg)$/,
        loader: 'file-loader',
        options: {
          name: '[name].[ext]?[hash]'
        }
      }
    ]
  },
  plugins: [
    new VueLoaderPlugin(),
    new webpack.DefinePlugin({
      'process.env.NODE_ENV': JSON.stringify(mode),
      __VUE_OPTIONS_API__: true,
      __VUE_PROD_DEVTOOLS__: false,
      __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: false,
      BURNBOX_VERSION: JSON.stringify(process.env.BURNBOX_VERSION || commitShaId || 'dev')
    }),
  ],
  devServer: {
    historyApiFallback: true,
    host: '0.0.0.0',
    proxy: [
      // Proxy requests to BE in DEV mode
      // https://webpack.github.io/docs/webpack-dev-server.html#proxy
      {
        context: ['/**'],
        target: 'http://localhost:3000/'
      }
    ]
  },
  performance: {
    hints: false
  },
};

if (process.env.ANALYZE) {
  module.exports.plugins.push(new BundleAnalyzerPlugin());
}
