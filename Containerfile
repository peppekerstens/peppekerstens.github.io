FROM ghcr.io/ruby/ruby:3.2.1-jammy

WORKDIR /site

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle lock --update && bundle install

COPY . .

CMD ["bundle", "exec", "jekyll", "build"]
